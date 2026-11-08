package com.aras.titistar

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.opengl.*
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.*

/**
 * Encoder-surface counterpart of the preview renderer. Every decoded frame is consumed exactly
 * once; no wall-clock playback, frame dropping or PNG files. All EGL/GL calls stay on the owning
 * export worker. Only SurfaceTexture event delivery and ML Kit run on separate threads.
 */
internal class TiniRetouchExportGl(
    output: Surface,
    private val width: Int,
    private val height: Int,
    private val cancelled: () -> Boolean,
) {
    // Keep the preview's spatial smoothing strength at export resolution.
    // Only sampling distances use this reference; all picture FBOs remain at
    // the requested full output dimensions, without reducing output quality.
    private val referenceScale = min(1f, 720f / max(width, height))
    private val referenceWidth = max(2, (width * referenceScale).roundToInt())
    private var display = EGL14.EGL_NO_DISPLAY
    private var context = EGL14.EGL_NO_CONTEXT
    private var window = EGL14.EGL_NO_SURFACE
    private var input: SurfaceTexture? = null
    private var ownedDecoderSurface: Surface? = null
    val decoderSurface: Surface
        get() = ownedDecoderSurface ?: error("Decoder surface is closed")

    private val events = HandlerThread("TiniRetouchExportFrames").apply { start() }
    private val frameReady = Semaphore(0)
    private val detectionReady = Semaphore(0)
    private val closed = AtomicBoolean(false)

    private data class Detection(
        val masks: List<Bitmap>,
        val regions: List<TiniRetouchRegion>,
        val count: Int,
    )

    var faceCount: Int = 0
        private set

    private val detected = AtomicReference<Detection?>(null)
    private val detectionError = AtomicReference<String?>(null)
    private val maskTextures = mutableListOf<Int>()
    private var maskRegions = emptyList<TiniRetouchRegion>()
    private var maskValid = false
    private var frameSerial = 0L
    private var lastCapture = Long.MIN_VALUE
    private val motion = TiniRetouchMotion()
    private val programs = mutableMapOf<String, Program>()
    private var oes = 0
    private var sharp: Target? = null
    private var horizontal: Target? = null
    private var vertical: Target? = null
    private var tracking: Target? = null
    private var flowTarget: Target? = null
    private var warpedMask: Target? = null
    private var trackingReadback: ByteBuffer? = null
    private var flowReadback: ByteBuffer? = null
    private var argb = IntArray(0)
    private var gray = ByteArray(0)
    private val matrix = FloatArray(16)
    private val identity = FloatArray(16).also { Matrix.setIdentityM(it, 0) }
    private val vertices = floats(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
    private val uvs = floats(floatArrayOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f))
    private val tracker =
        TiniRetouchTracker(
            deliver = { bitmaps, count, _, _, regions ->
                val result = Detection(bitmaps, regions, count)
                if (closed.get()) bitmaps.forEach { it.recycle() }
                else {
                    detected.getAndSet(result)?.masks?.forEach { it.recycle() }
                    if (closed.get()) detected.getAndSet(null)?.masks?.forEach { it.recycle() }
                }
                detectionReady.release()
            },
            failure = { message ->
                detectionError.set(message)
                detectionReady.release()
            },
        )

    init {
        try {
            require(width > 1 && height > 1)
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            val version = IntArray(2)
            check(EGL14.eglInitialize(display, version, 0, version, 1)) {
                "EGL initialization failed"
            }
            val configs = arrayOfNulls<EGLConfig>(1)
            val count = IntArray(1)
            // EGL_RECORDABLE_ANDROID is required for a MediaCodec input surface.
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
                    0x3142,
                    1,
                    EGL14.EGL_NONE,
                )
            check(
                EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, count, 0) &&
                    count[0] > 0
            ) {
                "No recordable EGL configuration"
            }
            val config = configs[0]
            context =
                EGL14.eglCreateContext(
                    display,
                    config,
                    EGL14.EGL_NO_CONTEXT,
                    intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
                    0,
                )
            check(context != EGL14.EGL_NO_CONTEXT) { "EGL context creation failed" }
            window =
                EGL14.eglCreateWindowSurface(display, config, output, intArrayOf(EGL14.EGL_NONE), 0)
            check(
                window != EGL14.EGL_NO_SURFACE &&
                    EGL14.eglMakeCurrent(display, window, window, context)
            ) {
                "Encoder EGL surface creation failed"
            }
            programs["external"] = Program(TiniRetouchShaders.external)
            programs["copy"] = Program(TiniRetouchShaders.copy)
            programs["warpMask"] = Program(TiniRetouchShaders.warpMask)
            programs["blur"] = Program(TiniRetouchShaders.blur)
            programs["retouch"] = Program(TiniRetouchShaders.retouch)
            sharp = Target(width, height)
            horizontal = Target(width, height)
            vertical = Target(width, height)
            warpedMask = Target(width, height)
            val trackingScale = min(1f, 480f / max(width, height))
            val tw = max(2, (width * trackingScale).roundToInt())
            val th = max(2, (height * trackingScale).roundToInt())
            tracking = Target(tw, th)
            trackingReadback = ByteBuffer.allocateDirect(tw * th * 4).order(ByteOrder.nativeOrder())
            argb = IntArray(tw * th)
            val flowScale = min(1f, 192f / max(width, height))
            val fw = max(12, (width * flowScale).roundToInt())
            val fh = max(12, (height * flowScale).roundToInt())
            flowTarget = Target(fw, fh)
            flowReadback = ByteBuffer.allocateDirect(fw * fh * 4).order(ByteOrder.nativeOrder())
            gray = ByteArray(fw * fh)
            oes = texture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES)
            input =
                SurfaceTexture(oes).apply {
                    setDefaultBufferSize(width, height)
                    setOnFrameAvailableListener({ frameReady.release() }, Handler(events.looper))
                }
            ownedDecoderSurface = Surface(input)
        } catch (error: Throwable) {
            close()
            throw error
        }
    }

    private fun await(signal: Semaphore, description: String) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        while (!signal.tryAcquire(50, TimeUnit.MILLISECONDS)) {
            check(!closed.get() && !cancelled()) { "Export cancelled" }
            check(SystemClock.elapsedRealtime() < deadline) { "Timed out waiting for $description" }
        }
        check(!closed.get() && !cancelled()) { "Export cancelled" }
    }

    /** Called after releasing one decoder output buffer to [decoderSurface]. */
    fun awaitFrameAndDraw(presentationUs: Long, smooth: Float, teeth: Float) {
        await(frameReady, "decoded video frame")
        input!!.updateTexImage()
        // SurfaceTexture supplies the decoder's crop/rotation transform. Apply
        // it once to the sharp target; tracking and final output share pixels.
        input!!.getTransformMatrix(matrix)
        render(programs.getValue("external"), sharp, oes, GLES11Ext.GL_TEXTURE_EXTERNAL_OES, matrix)
        val active = smooth > 0f || teeth > 0f
        if (active) {
            updateMotion(sharp!!)
            val refresh =
                !maskValid ||
                    lastCapture == Long.MIN_VALUE ||
                    presentationUs < lastCapture ||
                    presentationUs - lastCapture >= 125_000L
            if (refresh) detect(presentationUs)
        } else {
            // A later segment must detect on its first active frame rather than
            // reusing a mask across an untracked/off interval or scene cut.
            motion.reset()
            maskValid = false
            faceCount = 0
        }
        val warps = if (active && maskValid) motion.warps() else emptyList()
        val valid = warps.isNotEmpty()
        if (valid) warpMask(warps)
        var soft = sharp!!.texture
        if (valid && smooth > 0f) {
            render(programs.getValue("blur"), horizontal, sharp!!.texture) { p ->
                bind(p, "uMask", warpedMask!!.texture, 1)
                GLES20.glUniform2f(p.uniform("uStep"), 1f / (width * referenceScale), 0f)
            }
            render(programs.getValue("blur"), vertical, horizontal!!.texture) { p ->
                bind(p, "uMask", warpedMask!!.texture, 1)
                GLES20.glUniform2f(p.uniform("uStep"), 0f, 1f / (height * referenceScale))
            }
            soft = vertical!!.texture
        }
        render(programs.getValue("retouch"), null, sharp!!.texture) { p ->
            bind(p, "uSoft", soft, 1)
            bind(p, "uMask", warpedMask!!.texture, 2)
            GLES20.glUniform1f(p.uniform("uSmooth"), smooth.coerceIn(0f, 1f))
            GLES20.glUniform1f(p.uniform("uTeeth"), teeth.coerceIn(0f, 1f))
            GLES20.glUniform1f(p.uniform("uMaskEnabled"), if (valid) 1f else 0f)
        }
        check(EGLExt.eglPresentationTimeANDROID(display, window, presentationUs * 1000L)) {
            "Could not set encoder timestamp"
        }
        check(EGL14.eglSwapBuffers(display, window)) { "Encoder GPU surface was lost" }
    }

    private fun detect(presentationUs: Long) {
        val target = tracking!!
        render(programs.getValue("copy"), target, sharp!!.texture)
        val buffer = trackingReadback!!
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
            argb[(target.height - 1 - y) * target.width + x] =
                Color.rgb(
                    buffer.get(i).toInt() and 255,
                    buffer.get(i + 1).toInt() and 255,
                    buffer.get(i + 2).toInt() and 255,
                )
        }
        detectionReady.drainPermits()
        detectionError.set(null)
        // The detector marks itself idle after invoking deliver. Wait only for
        // that completion if it is still finishing its preceding callback.
        val deadline = SystemClock.elapsedRealtime() + 15_000
        while (!tracker.acquire()) {
            check(!cancelled() && !closed.get()) { "Export cancelled" }
            check(SystemClock.elapsedRealtime() < deadline) {
                "Face detector did not become available"
            }
            Thread.sleep(2)
        }
        try {
            tracker.offer(argb, target.width, target.height, referenceWidth, 0L, presentationUs)
        } catch (error: Throwable) {
            tracker.abandon()
            throw error
        }
        await(detectionReady, "face analysis")
        detectionError.getAndSet(null)?.let { error(it) }
        val result = detected.getAndSet(null) ?: error("Face analysis returned no result")
        try {
            check(motion.anchor(motion.frameId, result.regions)) {
                "Face analysis has no source frame"
            }
            while (maskTextures.size < result.masks.size) maskTextures.add(
                texture(GLES20.GL_TEXTURE_2D)
            )
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            for ((i, bitmap) in result.masks.withIndex()) {
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, maskTextures[i])
                GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
            }
            maskRegions = result.regions
            faceCount = result.count
            maskValid = true
            lastCapture = presentationUs
        } finally {
            result.masks.forEach { it.recycle() }
        }
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

    /** Must be called on the worker which constructed this EGL context. */
    fun close() {
        if (!closed.compareAndSet(false, true)) return
        tracker.close()
        detected.getAndSet(null)?.masks?.forEach { it.recycle() }
        try {
            ownedDecoderSurface?.release()
            ownedDecoderSurface = null
            input?.setOnFrameAvailableListener(null)
            input?.release()
            input = null
            if (context != EGL14.EGL_NO_CONTEXT) {
                listOf(sharp, horizontal, vertical, tracking, flowTarget, warpedMask).forEach {
                    it?.release()
                }
                programs.values.forEach { GLES20.glDeleteProgram(it.id) }
                if (oes != 0) GLES20.glDeleteTextures(1, intArrayOf(oes), 0)
                if (maskTextures.isNotEmpty())
                    GLES20.glDeleteTextures(maskTextures.size, maskTextures.toIntArray(), 0)
            }
        } finally {
            if (display != EGL14.EGL_NO_DISPLAY) {
                EGL14.eglMakeCurrent(
                    display,
                    EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_CONTEXT,
                )
                if (window != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, window)
                if (context != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, context)
                EGL14.eglReleaseThread()
                EGL14.eglTerminate(display)
            }
            events.quitSafely()
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
