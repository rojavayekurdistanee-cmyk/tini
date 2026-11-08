package com.aras.titistar

import android.app.Activity
import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

/** Owns a hardware decoder and Flutter texture per visible retouch preview. */
class TiniRetouchPreviewChannel(private val engine: FlutterEngine, private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private val players = mutableMapOf<Int, Preview>()
    private val next = AtomicInteger(1)
    private val channel =
        MethodChannel(engine.dartExecutor.binaryMessenger, "titi_star/retouch_gpu")
    private var closed = false

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.error("CLOSED", "Preview channel is closed", null)
            return
        }
        if (call.method == "create") {
            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("PATH", "Video path is missing", null)
                return
            }
            val id = next.getAndIncrement()
            try {
                val preview = Preview(id, path, result)
                players[id] = preview
                preview.open()
            } catch (error: Exception) {
                players.remove(id)?.close(notifyInitialization = false)
                result.error("GPU_PREVIEW", error.message, null)
            }
            return
        }
        val id = (call.argument<Number>("id"))?.toInt()
        val player = players[id]
        if (player == null) {
            if (call.method == "dispose") result.success(null)
            else result.error("NOT_FOUND", "Preview was released", null)
            return
        }
        try {
            when (call.method) {
                "state" -> {
                    result.success(player.state())
                    return
                }
                "play" -> player.play()
                "pause" -> player.pause()
                "seek" -> player.seek((call.argument<Number>("positionMs"))?.toLong() ?: 0)
                "volume" -> player.volume((call.argument<Number>("volume"))?.toFloat() ?: 1f)
                "speed" -> player.speed((call.argument<Number>("speed"))?.toFloat() ?: 1f)
                "loop" -> player.loop(call.argument<Boolean>("looping") == true)
                "settings" -> player.settings(call)
                "dispose" -> {
                    players.remove(id)
                    player.close()
                }
                else -> {
                    result.notImplemented()
                    return
                }
            }
            result.success(null)
        } catch (error: Exception) {
            result.error("GPU_PREVIEW", error.message, null)
        }
    }

    fun pauseAll() {
        players.values.toList().forEach { it.suspend() }
    }

    fun resumeAll() {
        players.values.toList().forEach { it.resume() }
    }

    fun dispose() {
        if (closed) return
        closed = true
        channel.setMethodCallHandler(null)
        players.values.toList().forEach { it.close() }
        players.clear()
    }

    private data class Region(val start: Long, val end: Long, val smooth: Float, val teeth: Float)

    private inner class Preview(
        val id: Int,
        val path: String,
        private var initialization: MethodChannel.Result?,
    ) {
        private val entry = engine.renderer.createSurfaceTexture()
        private val player = MediaPlayer()
        private val power = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        private var prepared = false
        private var released = false
        private var priming = false
        private var completed = false
        private var requestedVolume = 1f
        private var videoWidth = 1
        private var videoHeight = 1
        private var duration = 0L
        private var error: String? = null
        private var thermalPaused = false
        @Volatile private var constant = Pair(0f, 0f)
        @Volatile private var regions: List<Region> = emptyList()
        private var thermalStatus =
            if (Build.VERSION.SDK_INT >= 29) power.currentThermalStatus else 0
        private val renderer =
            TiniRetouchRenderer(
                entry,
                ::amounts,
                { main.post { firstFrame() } },
                { message -> main.post { fail(message) } },
            )
        private val ticker =
            object : Runnable {
                override fun run() {
                    if (released || !prepared) return
                    val playing = player.isPlaying
                    renderer.setClock(player.currentPosition.toLong(), playing)
                    if (playing) main.postDelayed(this, 33)
                }
            }
        private val thermalListener: PowerManager.OnThermalStatusChangedListener? =
            if (Build.VERSION.SDK_INT >= 29)
                PowerManager.OnThermalStatusChangedListener { status ->
                    if (!released) {
                        thermalStatus = status
                        renderer.budget(status)
                        if (status >= 4) {
                            thermalPaused = true
                            pause()
                        }
                    }
                }
            else null

        fun open() {
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                    .build()
            )
            player.setOnErrorListener { _, what, extra ->
                fail("تعذر فك الفيديو ($what/$extra)")
                true
            }
            player.setOnCompletionListener {
                completed = true
                renderer.setClock(duration, false)
                main.removeCallbacks(ticker)
            }
            player.setOnSeekCompleteListener {
                renderer.seekCompleted()
                renderer.setClock(player.currentPosition.toLong(), player.isPlaying)
            }
            player.setOnPreparedListener {
                if (released) return@setOnPreparedListener
                prepared = true
                duration = player.duration.toLong()
                videoWidth = player.videoWidth
                videoHeight = player.videoHeight
                renderer.configure(videoWidth, videoHeight) {
                    main.post {
                        if (!released) {
                            renderer.budget(thermalStatus)
                            priming = true
                            player.setVolume(0f, 0f)
                            player.start()
                            ticker.run()
                        }
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= 29 && thermalListener != null)
                power.addThermalStatusListener(activity.mainExecutor, thermalListener)
            // MediaPlayer reports display dimensions with rotation already applied.
            // The decoder's SurfaceTexture matrix carries crop/rotation for pixels.
            // Reading metadata and applying that rotation again rotates portraits twice.
            renderer.start { surface ->
                main.post {
                    if (!released) {
                        try {
                            player.setSurface(surface)
                            player.setDataSource(path)
                            player.prepareAsync()
                        } catch (problem: Exception) {
                            fail(problem.message ?: "Unable to open video")
                        }
                    }
                }
            }
        }

        private fun firstFrame() {
            if (released || !priming) return
            priming = false
            player.pause()
            renderer.setClock(player.currentPosition.toLong(), false)
            player.setVolume(requestedVolume, requestedVolume)
            main.removeCallbacks(ticker)
            val w = videoWidth
            val h = videoHeight
            initialization?.success(
                mapOf(
                    "id" to id,
                    "textureId" to entry.id(),
                    "width" to w,
                    "height" to h,
                    "durationMs" to duration,
                )
            )
            initialization = null
        }

        private fun fail(message: String) {
            if (released) return
            val opening = initialization != null
            error = message
            initialization?.error("GPU_PREVIEW", message, null)
            initialization = null
            if (!prepared || opening) {
                players.remove(id)
                close()
            } else {
                pause()
                renderer.suspend()
            }
        }

        fun settings(call: MethodCall) {
            constant =
                Pair(
                    (call.argument<Number>("smooth")?.toFloat() ?: 0f).coerceIn(0f, 1f),
                    (call.argument<Number>("teeth")?.toFloat() ?: 0f).coerceIn(0f, 1f),
                )
            val data = call.argument<List<Map<String, Any?>>>("regions") ?: emptyList()
            regions =
                data.mapNotNull { row ->
                    val start = (row["startMs"] as? Number)?.toLong() ?: return@mapNotNull null
                    val end = (row["endMs"] as? Number)?.toLong() ?: return@mapNotNull null
                    if (end <= start) return@mapNotNull null
                    Region(
                        start,
                        end,
                        ((row["smooth"] as? Number)?.toFloat() ?: 0f).coerceIn(0f, 1f),
                        ((row["teeth"] as? Number)?.toFloat() ?: 0f).coerceIn(0f, 1f),
                    )
                }
            renderer.settingsChanged()
        }

        private fun amounts(at: Long): Pair<Float, Float> {
            val timeline = regions
            if (timeline.isEmpty()) return constant
            val region =
                timeline.firstOrNull { at >= it.start && at < it.end } ?: return Pair(0f, 0f)
            return Pair(region.smooth, region.teeth)
        }

        fun play() {
            check(prepared && !released)
            if (thermalStatus >= 4)
                throw IllegalStateException("أوقف الجهاز المعاينة مؤقتًا بسبب الحرارة")
            thermalPaused = false
            completed = false
            renderer.resume()
            player.start()
            main.removeCallbacks(ticker)
            ticker.run()
        }

        fun pause() {
            if (prepared && !released) {
                player.pause()
                renderer.setClock(player.currentPosition.toLong(), false)
                renderer.pauseFrame()
                main.removeCallbacks(ticker)
            }
        }

        fun seek(ms: Long) {
            if (!prepared || released) return
            completed = false
            renderer.seek()
            renderer.setClock(ms, player.isPlaying)
            if (Build.VERSION.SDK_INT >= 26)
                player.seekTo(ms.coerceIn(0, duration), MediaPlayer.SEEK_CLOSEST)
            else player.seekTo(ms.coerceIn(0, duration).toInt())
        }

        fun volume(v: Float) {
            requestedVolume = v.coerceIn(0f, 1f)
            if (prepared && !priming) player.setVolume(requestedVolume, requestedVolume)
        }

        fun speed(v: Float) {
            if (prepared) {
                val wasPlaying = player.isPlaying
                player.playbackParams = player.playbackParams.setSpeed(v.coerceIn(.1f, 10f))
                if (!wasPlaying) player.pause()
            }
        }

        fun loop(value: Boolean) {
            player.isLooping = value
        }

        fun state(): Map<String, Any?> {
            val at = if (prepared && !released) player.currentPosition.toLong() else 0L
            val playing = prepared && !released && player.isPlaying && !priming
            renderer.setClock(at, playing)
            return mapOf(
                "positionMs" to at,
                "playing" to playing,
                "completed" to completed,
                "faces" to renderer.faces,
                "tracking" to renderer.isTracking,
                "thermalStatus" to thermalStatus,
                "thermalPaused" to thermalPaused,
                "error" to error,
            )
        }

        fun suspend() {
            pause()
            renderer.suspend()
        }

        fun resume() {
            renderer.resume()
        }

        fun close(notifyInitialization: Boolean = true) {
            if (released) return
            released = true
            main.removeCallbacks(ticker)
            if (Build.VERSION.SDK_INT >= 29 && thermalListener != null)
                power.removeThermalStatusListener(thermalListener)
            if (notifyInitialization) initialization?.error("CANCELLED", "Preview was closed", null)
            initialization = null
            player.release()
            renderer.close { main.post { entry.release() } }
        }
    }
}
