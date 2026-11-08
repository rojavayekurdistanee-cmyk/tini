package com.aras.titistar

import android.graphics.SurfaceTexture
import android.opengl.*
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.view.Surface
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.*

/**
 * Event-driven OpenGL pipeline: OES video -> sharp FBO -> separable face blur -> localized retouch
 * -> Flutter texture. No per-frame Dart messages/files.
 */
internal class TiniRetouchRenderer(
    private val entry: TextureRegistry.SurfaceTextureEntry,
    private val strengths: (Long) -> Pair<Float, Float>,
    private val firstFrame: () -> Unit,
    private val failure: (String) -> Unit,
) {
    private val thread = HandlerThread("TiniRetouchGL").apply { start() }
    private val handler = Handler(thread.looper)
    private var display = EGL14.EGL_NO_DISPLAY
    private var context = EGL14.EGL_NO_CONTEXT
    private var window = EGL14.EGL_NO_SURFACE
    private var config: EGLConfig? = null
    private var output: Surface? = null
    private var input: SurfaceTexture? = null
    private var inputSurface: Surface? = null
    private var oes = 0
    private val maskTextures = mutableListOf<Int>()
    private var maskRegions = emptyList<TiniRetouchRegion>()
    private val programs = mutableMapOf<String, Program>()
    private var sharp: Target? = null
    private var horizontal: Target? = null
    private var vertical: Target? = null
    private var tracking: Target? = null
    private var flowTarget: Target? = null
    private var warpedMask: Target? = null
    private var flowReadback: ByteBuffer? = null
    private var gray = ByteArray(0)
    private val motion = TiniRetouchMotion()
    private var frameSerial = 0L
    private var pendingFrame = -1L
    private var awaitingMask = false
    private var readback: ByteBuffer? = null
    private var argb = IntArray(0)
    private var sourceWidth = 1
    private var sourceHeight = 1
    private var width = 1
    private var height = 1
    private var maxEdge = 720
    private var fps = 30
    private var trackingInterval = 125L
    private var lastDraw = 0L
    private var lastCapture = 0L
    private var sourceAt = 0L
    private var epoch = 0L
    private var sharpDirty = false
    private var seekPending = false
    private var hasFrame = false
    private var frameAvailable = false
    private var scheduled = false
    private var forceTracking = true
    private var maskValid = false
    private var announced = false
    @Volatile private var released = false
    @Volatile private var suspended = false
    @Volatile private var playing = false
    @Volatile private var clock = 0L
    @Volatile
    var faces = -1
        private set

    val isTracking: Boolean
        get() = tracker.isBusy

    private val identity = FloatArray(16).also { Matrix.setIdentityM(it, 0) }
    private val matrix = FloatArray(16)
    private val vertices = floats(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
    private val uvs = floats(floatArrayOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f))
    private val tracker =
        TiniRetouchTracker(
            deliver = { bitmaps, count, generation, _, regions ->
                if (
                    !handler.post {
                        try {
                            if (
                                !released &&
                                    generation == epoch &&
                                    motion.anchor(pendingFrame, regions)
                            ) {
                                GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
                                while (maskTextures.size < bitmaps.size) {
                                    maskTextures.add(texture(GLES20.GL_TEXTURE_2D))
                                }
                                for ((index, bitmap) in bitmaps.withIndex()) {
                                    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, maskTextures[index])
                                    GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
                                }
                                maskRegions = regions
                                maskValid = true
                                faces = count
                                schedule(true)
                            } else if (!released) {
                                forceTracking = true
                            }
                        } finally {
                            awaitingMask = false
                            bitmaps.forEach { it.recycle() }
                            if (!released && forceTracking) schedule(true)
                        }
                    }
                )
                    bitmaps.forEach { it.recycle() }
            },
            failure = failure,
        )

    fun start(ready: (Surface) -> Unit) {
        handler.post {
            try {
                display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
                val version = IntArray(2)
                check(EGL14.eglInitialize(display, version, 0, version, 1)) {
                    "EGL initialization failed"
                }
                val configs = arrayOfNulls<EGLConfig>(1)
                val count = IntArray(1)
                val attributes =
                    intArrayOf(
                        EGL14.EGL_RED_SIZE,
                        8,
                        EGL14.EGL_GREEN_SIZE,
                        8,
                        EGL14.EGL_BLUE_SIZE,
                        8,
                        EGL14.EGL_ALPHA_SIZE,
                        8,
                        EGL14.EGL_SURFACE_TYPE,
                        EGL14.EGL_WINDOW_BIT,
                        EGL14.EGL_RENDERABLE_TYPE,
                        EGL14.EGL_OPENGL_ES2_BIT,
                        EGL14.EGL_NONE,
                    )
                check(
                    EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, count, 0) &&
                        count[0] > 0
                )
                config = configs[0]
                context =
                    EGL14.eglCreateContext(
                        display,
                        config,
                        EGL14.EGL_NO_CONTEXT,
                        intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
                        0,
                    )
                check(context != EGL14.EGL_NO_CONTEXT)
                entry.surfaceTexture().setDefaultBufferSize(720, 720)
                output = Surface(entry.surfaceTexture())
                createWindow()
                programs["external"] = Program(TiniRetouchShaders.external)
                programs["copy"] = Program(TiniRetouchShaders.copy)
                programs["warpMask"] = Program(TiniRetouchShaders.warpMask)
                programs["blur"] = Program(TiniRetouchShaders.blur)
                programs["retouch"] = Program(TiniRetouchShaders.retouch)
                oes = texture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES)
                input =
                    SurfaceTexture(oes).apply {
                        setOnFrameAvailableListener(
                            {
                                frameAvailable = true
                                schedule(false)
                            },
                            handler,
                        )
                    }
                inputSurface = Surface(input)
                ready(inputSurface!!)
            } catch (error: Exception) {
                failure(error.message ?: "GPU initialization failed")
            }
        }
    }

    private fun createWindow() {
        if (window != EGL14.EGL_NO_SURFACE) {
            EGL14.eglMakeCurrent(
                display,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_CONTEXT,
            )
            EGL14.eglDestroySurface(display, window)
        }
        window =
            EGL14.eglCreateWindowSurface(display, config, output, intArrayOf(EGL14.EGL_NONE), 0)
        check(
            window != EGL14.EGL_NO_SURFACE && EGL14.eglMakeCurrent(display, window, window, context)
        )
    }

    fun configure(videoWidth: Int, videoHeight: Int, done: () -> Unit) {
        handler.post {
            try {
                // These are MediaPlayer display dimensions, not encoded frame dimensions.
                sourceWidth = videoWidth
                sourceHeight = videoHeight
                require(sourceWidth > 0 && sourceHeight > 0)
                resize()
                done()
            } catch (error: Exception) {
                failure(error.message ?: "Invalid video dimensions")
            }
        }
    }

    private fun resize() {
        val scale = min(1f, maxEdge.toFloat() / max(sourceWidth, sourceHeight))
        width = max(2, (sourceWidth * scale).roundToInt())
        height = max(2, (sourceHeight * scale).roundToInt())
        listOf(sharp, horizontal, vertical, tracking, flowTarget, warpedMask).forEach {
            it?.release()
        }
        entry.surfaceTexture().setDefaultBufferSize(width, height)
        createWindow()
        sharp = Target(width, height)
        horizontal = Target(width, height)
        vertical = Target(width, height)
        val trackingEdge = if (maxEdge < 720) 320 else 480
        val ratio = min(1f, trackingEdge.toFloat() / max(width, height))
        val tw = max(2, (width * ratio).roundToInt())
        val th = max(2, (height * ratio).roundToInt())
        tracking = Target(tw, th)
        val flowScale = min(1f, 192f / max(width, height))
        val fw = max(12, (width * flowScale).roundToInt())
        val fh = max(12, (height * flowScale).roundToInt())
        flowTarget = Target(fw, fh)
        warpedMask = Target(width, height)
        flowReadback = ByteBuffer.allocateDirect(fw * fh * 4).order(ByteOrder.nativeOrder())
        gray = ByteArray(fw * fh)
        motion.reset()
        epoch++
        readback = ByteBuffer.allocateDirect(tw * th * 4).order(ByteOrder.nativeOrder())
        argb = IntArray(tw * th)
        maskValid = false
        forceTracking = true
        sharpDirty = true
    }

    fun setClock(position: Long, isPlaying: Boolean) {
        clock = position
        playing = isPlaying
    }

    fun settingsChanged() {
        handler.post {
            if (!maskValid) forceTracking = true
            schedule(true)
        }
    }

    fun seek() {
        handler.post {
            epoch++
            motion.reset()
            maskValid = false
            faces = -1
            forceTracking = true
            seekPending = true
        }
    }

    fun seekCompleted() {
        handler.post {
            seekPending = false
            forceTracking = true
            schedule(true)
        }
    }

    fun pauseFrame() {
        handler.post {
            forceTracking = true
            schedule(true)
        }
    }

    fun suspend() {
        suspended = true
    }

    fun resume() {
        suspended = false
        handler.post { schedule(true) }
    }

    fun budget(status: Int) {
        handler.post {
            if (released) return@post
            val edge = if (status >= 3) 480 else if (status >= 2) 600 else 720
            fps = if (status >= 3) 15 else if (status >= 2) 24 else 30
            trackingInterval = if (status >= 3) 500 else if (status >= 2) 250 else 125
            if (maxEdge != edge) {
                maxEdge = edge
                if (sharp != null) resize()
            }
            schedule(true)
        }
    }

    private fun schedule(force: Boolean) {
        if (released || suspended || scheduled) return
        scheduled = true
        val delay =
            if (force) 0 else max(0L, 1000L / fps - (SystemClock.elapsedRealtime() - lastDraw))
        handler.postDelayed(
            {
                scheduled = false
                if (!released && !suspended)
                    try {
                        draw()
                    } catch (error: Exception) {
                        failure(error.message ?: "GPU rendering failed")
                    }
            },
            delay,
        )
    }

    private fun draw() {
        val sharp = sharp ?: return
        val now = SystemClock.elapsedRealtime()
        if (frameAvailable) {
            input!!.updateTexImage()
            // Use the decoder transform exactly once, including crop and orientation.
            // This upright sharp FBO feeds both Flutter output and ML Kit readback.
            input!!.getTransformMatrix(matrix)
            val pts = input!!.timestamp / 1000000
            sourceAt = if (abs(pts - clock) < 500) pts else clock
            frameAvailable = false
            hasFrame = true
            sharpDirty = true
        }
        if (!hasFrame) return
        if (sharpDirty) {
            render(
                programs.getValue("external"),
                sharp,
                oes,
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                matrix,
            )
            updateMotion(sharp)
            sharpDirty = false
        } else if (motion.frameId < 0) {
            // Seeking to the already-paused frame may not emit another decoder frame.
            updateMotion(sharp)
        }
        val amounts = strengths(sourceAt)
        val warps = if (maskValid) motion.warps() else emptyList()
        val valid = warps.isNotEmpty()
        if (valid) warpMask(warps)
        val smooth = amounts.first.coerceIn(0f, 1f)
        val teeth = amounts.second.coerceIn(0f, 1f)
        var soft = sharp.texture
        if (valid && smooth > 0) {
            render(programs.getValue("blur"), horizontal, sharp.texture) { p ->
                bind(p, "uMask", warpedMask!!.texture, 1)
                GLES20.glUniform2f(p.uniform("uStep"), 1f / width, 0f)
            }
            render(programs.getValue("blur"), vertical, horizontal!!.texture) { p ->
                bind(p, "uMask", warpedMask!!.texture, 1)
                GLES20.glUniform2f(p.uniform("uStep"), 0f, 1f / height)
            }
            soft = vertical!!.texture
        }
        render(programs.getValue("retouch"), null, sharp.texture) { p ->
            bind(p, "uSoft", soft, 1)
            bind(p, "uMask", warpedMask!!.texture, 2)
            GLES20.glUniform1f(p.uniform("uSmooth"), smooth)
            GLES20.glUniform1f(p.uniform("uTeeth"), teeth)
            GLES20.glUniform1f(p.uniform("uMaskEnabled"), if (valid) 1f else 0f)
        }
        check(EGL14.eglSwapBuffers(display, window)) { "GPU surface was lost" }
        lastDraw = now
        if (!announced) {
            announced = true
            firstFrame()
        }
        if (
            !seekPending &&
                (forceTracking ||
                    ((smooth > 0 || teeth > 0) &&
                        playing &&
                        now - lastCapture >= trackingInterval)) &&
                !awaitingMask &&
                tracker.acquire()
        ) {
            try {
                val target = tracking!!
                render(programs.getValue("copy"), target, sharp.texture)
                val buffer = readback!!
                buffer.position(0)
                GLES20.glReadPixels(
                    0,
                    0,
                    target.width,
                    target.height,
                    GLES20.GL_RGBA,
                    GLES20.GL_UNSIGNED_BYTE,
                    buffer,
                )
                for (y in 0 until target.height) for (x in 0 until target.width) {
                    val offset = (y * target.width + x) * 4
                    argb[(target.height - 1 - y) * target.width + x] =
                        android.graphics.Color.rgb(
                            buffer.get(offset).toInt() and 255,
                            buffer.get(offset + 1).toInt() and 255,
                            buffer.get(offset + 2).toInt() and 255,
                        )
                }
                forceTracking = false
                lastCapture = now
                pendingFrame = motion.frameId
                awaitingMask = true
                tracker.offer(argb, target.width, target.height, width, epoch, now)
            } catch (error: Exception) {
                awaitingMask = false
                tracker.abandon()
                throw error
            }
        }
        if (forceTracking && tracker.isBusy) handler.postDelayed({ schedule(true) }, 40)
    }

    private fun updateMotion(source: Target) {
        val target = flowTarget!!
        render(programs.getValue("copy"), target, source.texture)
        val buffer = flowReadback!!
        buffer.position(0)
        GLES20.glReadPixels(
            0,
            0,
            target.width,
            target.height,
            GLES20.GL_RGBA,
            GLES20.GL_UNSIGNED_BYTE,
            buffer,
        )
        for (y in 0 until target.height) for (x in 0 until target.width) {
            val i = (y * target.width + x) * 4
            val r = buffer.get(i).toInt() and 255
            val g = buffer.get(i + 1).toInt() and 255
            val b = buffer.get(i + 2).toInt() and 255
            gray[(target.height - 1 - y) * target.width + x] =
                ((77 * r + 150 * g + 29 * b) shr 8).toByte()
        }
        motion.push(++frameSerial, target.width, target.height, gray)
    }

    private fun warpMask(warps: List<TiniRetouchMotion.Warp>) {
        val target = warpedMask!!
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, target.framebuffer)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE)
        try {
            for (warp in warps) {
                val index = maskRegions.indexOf(warp.region)
                val mask = maskTextures.getOrNull(index) ?: continue
                render(programs.getValue("warpMask"), target, mask) { p ->
                    GLES20.glUniformMatrix3fv(p.uniform("uFaceWarp"), 1, false, warp.face, 0)
                    GLES20.glUniformMatrix3fv(p.uniform("uMouthWarp"), 1, false, warp.mouth, 0)
                    val b = warp.region
                    GLES20.glUniform4f(p.uniform("uBounds"), b.left, b.top, b.right, b.bottom)
                    GLES20.glUniform1f(p.uniform("uTeethConfidence"), warp.teethConfidence)
                }
            }
        } finally {
            GLES20.glDisable(GLES20.GL_BLEND)
        }
    }

    private fun render(
        program: Program,
        target: Target?,
        source: Int,
        type: Int = GLES20.GL_TEXTURE_2D,
        transform: FloatArray = identity,
        extras: (Program) -> Unit = {},
    ) {
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, target?.framebuffer ?: 0)
        GLES20.glViewport(0, 0, target?.width ?: width, target?.height ?: height)
        GLES20.glUseProgram(program.id)
        GLES20.glUniformMatrix4fv(program.uniform("uMatrix"), 1, false, transform, 0)
        vertices.position(0)
        uvs.position(0)
        GLES20.glEnableVertexAttribArray(program.position)
        GLES20.glEnableVertexAttribArray(program.uv)
        GLES20.glVertexAttribPointer(program.position, 2, GLES20.GL_FLOAT, false, 0, vertices)
        GLES20.glVertexAttribPointer(program.uv, 2, GLES20.GL_FLOAT, false, 0, uvs)
        bind(program, "uFrame", source, 0, type)
        extras(program)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(program.position)
        GLES20.glDisableVertexAttribArray(program.uv)
    }

    private fun bind(
        program: Program,
        name: String,
        id: Int,
        unit: Int,
        type: Int = GLES20.GL_TEXTURE_2D,
    ) {
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0 + unit)
        GLES20.glBindTexture(type, id)
        GLES20.glUniform1i(program.uniform(name), unit)
    }

    fun close(done: () -> Unit) {
        if (released) return
        released = true
        tracker.close()
        handler.post {
            try {
                listOf(sharp, horizontal, vertical, tracking, flowTarget, warpedMask).forEach {
                    it?.release()
                }
                programs.values.forEach { GLES20.glDeleteProgram(it.id) }
                if (oes != 0) GLES20.glDeleteTextures(1, intArrayOf(oes), 0)
                if (maskTextures.isNotEmpty()) {
                    GLES20.glDeleteTextures(maskTextures.size, maskTextures.toIntArray(), 0)
                    maskTextures.clear()
                }
                inputSurface?.release()
                input?.release()
                EGL14.eglMakeCurrent(
                    display,
                    EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_CONTEXT,
                )
                if (window != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, window)
                if (context != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, context)
                if (display != EGL14.EGL_NO_DISPLAY) EGL14.eglTerminate(display)
                output?.release()
            } finally {
                thread.quitSafely()
                done()
            }
        }
    }

    private class Target(val width: Int, val height: Int) {
        val texture = texture(GLES20.GL_TEXTURE_2D)
        val framebuffer: Int

        init {
            GLES20.glTexImage2D(
                GLES20.GL_TEXTURE_2D,
                0,
                GLES20.GL_RGBA,
                width,
                height,
                0,
                GLES20.GL_RGBA,
                GLES20.GL_UNSIGNED_BYTE,
                null,
            )
            val ids = IntArray(1)
            GLES20.glGenFramebuffers(1, ids, 0)
            framebuffer = ids[0]
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, framebuffer)
            GLES20.glFramebufferTexture2D(
                GLES20.GL_FRAMEBUFFER,
                GLES20.GL_COLOR_ATTACHMENT0,
                GLES20.GL_TEXTURE_2D,
                texture,
                0,
            )
            check(
                GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER) ==
                    GLES20.GL_FRAMEBUFFER_COMPLETE
            )
        }

        fun release() {
            GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
            GLES20.glDeleteFramebuffers(1, intArrayOf(framebuffer), 0)
        }
    }

    private class Program(fragment: String) {
        val id: Int
        val position: Int
        val uv: Int
        private val uniforms = mutableMapOf<String, Int>()

        init {
            val vertex = compile(GLES20.GL_VERTEX_SHADER, TiniRetouchShaders.vertex)
            var pixel =
                try {
                    compile(GLES20.GL_FRAGMENT_SHADER, fragment)
                } catch (error: IllegalStateException) {
                    compile(GLES20.GL_FRAGMENT_SHADER, fragment.replace("highp", "mediump"))
                }
            id = GLES20.glCreateProgram()
            GLES20.glAttachShader(id, vertex)
            GLES20.glAttachShader(id, pixel)
            GLES20.glLinkProgram(id)
            val status = IntArray(1)
            GLES20.glGetProgramiv(id, GLES20.GL_LINK_STATUS, status, 0)
            GLES20.glDeleteShader(vertex)
            GLES20.glDeleteShader(pixel)
            check(status[0] != 0) { GLES20.glGetProgramInfoLog(id) }
            position = GLES20.glGetAttribLocation(id, "aPosition")
            uv = GLES20.glGetAttribLocation(id, "aUv")
        }

        fun uniform(name: String): Int =
            uniforms.getOrPut(name) { GLES20.glGetUniformLocation(id, name) }
    }

    companion object {
        private fun floats(values: FloatArray): FloatBuffer =
            ByteBuffer.allocateDirect(values.size * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
                .apply {
                    put(values)
                    position(0)
                }

        private fun texture(type: Int): Int {
            val ids = IntArray(1)
            GLES20.glGenTextures(1, ids, 0)
            GLES20.glBindTexture(type, ids[0])
            GLES20.glTexParameteri(type, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(type, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(type, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(type, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
            return ids[0]
        }

        private fun compile(type: Int, source: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, source)
            GLES20.glCompileShader(shader)
            val result = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, result, 0)
            if (result[0] == 0) {
                val log = GLES20.glGetShaderInfoLog(shader)
                GLES20.glDeleteShader(shader)
                error(log)
            }
            return shader
        }
    }
}
