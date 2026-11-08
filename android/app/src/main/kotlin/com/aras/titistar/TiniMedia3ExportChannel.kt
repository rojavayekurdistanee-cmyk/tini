
package com.aras.titistar

import android.content.Context
import android.graphics.Color
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.SpeedParameters
import androidx.media3.common.audio.SpeedProvider
import androidx.media3.common.audio.DefaultGainProvider
import androidx.media3.common.audio.GainProcessor
import androidx.media3.common.util.ExperimentalApi
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.SingleColorLut
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.pow

/**
 * Media3 export path. The Tini edit graph is still authoritative for effects
 * that have no Media3 implementation; native requests must never silently
 * ignore a requested effect.
 */
@OptIn(markerClass = [UnstableApi::class, ExperimentalApi::class])
class TiniMedia3ExportChannel(engine: FlutterEngine, private val context: Context) {
    private val channel = MethodChannel(
        engine.dartExecutor.binaryMessenger,
        "titi_star/media3_export"
    )

    private class Job(
        val transformer: Transformer,
        val output: File,
        val reply: MethodChannel.Result,
        val expectedDurationMs: Long?,
        val expectedFrames: Long?,
        val expectedWidth: Int?,
        val expectedHeight: Int?,
        val requireAudio: Boolean,
        val exactVideoFrameCount: Boolean = false,
        // Never accept an invisible second video encode after Tini effects.
        val requireVideoTransmux: Boolean = false
    )

    private data class Segment(
        val input: File,
        val startMs: Long,
        val endMs: Long?,
        val mute: Boolean,
        val colorMatrix: FloatArray?,
        val speed: Float = 1f
    )

    // MethodChannel callbacks and Transformer listeners execute on the main looper.
    private val jobs = mutableMapOf<String, Job>()
    private var closed = false

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, reply: MethodChannel.Result) {
        if (closed) {
            reply.error("CLOSED", "Media3 channel has been disposed", null)
            return
        }
        when (call.method) {
            "isAvailable" -> reply.success(true)
            "start" -> start(call, reply, timeline = false)
            "startTimeline" -> start(call, reply, timeline = true)
            "startMusicMix" -> startMusicMix(call, reply)
            "progress" -> {
                val job = jobs[call.argument<String>("id")]
                if (job == null) {
                    reply.success(mapOf("percent" to null))
                } else {
                    try {
                        val holder = ProgressHolder()
                        val state = job.transformer.getProgress(holder)
                        reply.success(mapOf(
                            "percent" to if (state == Transformer.PROGRESS_STATE_AVAILABLE)
                                holder.progress else null
                        ))
                    } catch (error: Exception) {
                        reply.error("PROGRESS", error.message, null)
                    }
                }
            }
            "cancel" -> {
                val id = call.argument<String>("id")
                val job = jobs.remove(id)
                if (job == null) {
                    reply.success(false)
                } else {
                    job.transformer.cancel()
                    job.output.delete()
                    job.reply.error("CANCELLED", "Video export cancelled", null)
                    reply.success(true)
                }
            }
            else -> reply.notImplemented()
        }
    }

    private fun matrixFrom(value: Any?): FloatArray? {
        if (value == null) return null
        val values = value as? List<*>
            ?: throw IllegalArgumentException("Colour matrix must be a list")
        require(values.size == 20) { "Colour matrix must have 20 coefficients" }
        val matrix = FloatArray(20) { index ->
            (values[index] as? Number)?.toFloat()
                ?: throw IllegalArgumentException("Invalid colour matrix coefficient")
        }
        require(matrix.all { it.isFinite() }) { "Colour matrix has non-finite coefficients" }
        require(matrix[15] == 0f && matrix[16] == 0f && matrix[17] == 0f &&
            matrix[18] == 1f && matrix[19] == 0f) {
            "Colour matrix may not alter alpha"
        }
        return matrix
    }

    private fun parseSegment(arguments: Map<*, *>): Segment {
        val inputPath = arguments["inputPath"] as? String
        val startMs = (arguments["startMs"] as? Number)?.toLong() ?: 0L
        val endMs = (arguments["endMs"] as? Number)?.toLong()
        val mute = arguments["mute"] as? Boolean ?: false
        require(!inputPath.isNullOrBlank() && startMs >= 0L &&
            (endMs == null || endMs > startMs)) { "Invalid Media3 clip request" }
        val input = File(inputPath)
        if (!input.isFile || !input.canRead()) {
            throw IllegalArgumentException(
                "Video source does not exist or cannot be read: $inputPath"
            )
        }
        val speed = (arguments["speed"] as? Number)?.toFloat() ?: 1f
        require(speed.isFinite() && speed in 0.1f..10f) {
            "Invalid Media3 clip speed"
        }
        return Segment(input, startMs, endMs, mute,
            matrixFrom(arguments["colorMatrix"]), speed)
    }

    private fun sRgbToLinear(value: Float): Float {
        val clamped = value.coerceIn(0f, 1f)
        return if (clamped <= 0.04045f) clamped / 12.92f
            else ((clamped + 0.055f) / 1.055f).toDouble().pow(2.4).toFloat()
    }

    private fun linearToSRgb(value: Float): Float {
        val clamped = value.coerceIn(0f, 1f)
        return if (clamped <= 0.0031308f) clamped * 12.92f
            else (1.055 * clamped.toDouble().pow(1.0 / 2.4) - 0.055).toFloat()
    }

    /**
     * Flutter's matrix offsets are in 0..255 sRGB. Media3's LUT input is
     * linear RGB. Convert into sRGB before applying the matrix, then convert
     * back so brightness and mixing do not silently disappear on the GPU.
     * The 33^3 LUT is an approximation and needs on-device visual comparison.
     */
    private fun buildColorEffect(matrix: FloatArray): SingleColorLut {
        val size = 33
        val cube = Array(size) { Array(size) { IntArray(size) } }
        for (r in 0 until size) {
            val red = linearToSRgb(r.toFloat() / (size - 1))
            for (g in 0 until size) {
                val green = linearToSRgb(g.toFloat() / (size - 1))
                for (b in 0 until size) {
                    val blue = linearToSRgb(b.toFloat() / (size - 1))
                    val channels = floatArrayOf(red, green, blue)
                    val output = IntArray(3) { row ->
                        var transformed = matrix[row * 5 + 4] / 255f
                        for (col in 0..2) {
                            transformed += matrix[row * 5 + col] * channels[col]
                        }
                        (sRgbToLinear(transformed) * 255f + 0.5f)
                            .toInt().coerceIn(0, 255)
                    }
                    cube[r][g][b] = Color.rgb(output[0], output[1], output[2])
                }
            }
        }
        return SingleColorLut.createFromCube(cube)
    }

    private fun edited(segment: Segment): EditedMediaItem {
        val clip = MediaItem.ClippingConfiguration.Builder()
            .setStartPositionMs(segment.startMs)
            .apply { if (segment.endMs != null) setEndPositionMs(segment.endMs) }
            .build()
        val item = MediaItem.Builder()
            .setUri(Uri.fromFile(segment.input))
            .setClippingConfiguration(clip)
            .build()
        val builder = EditedMediaItem.Builder(item)
            .setRemoveAudio(segment.mute)
        segment.colorMatrix?.let {
            builder.setEffects(Effects(emptyList(), listOf(buildColorEffect(it))))
        }
        if (abs(segment.speed - 1f) > 0.00001f) {
            // Preserve the source audio pitch as FFmpeg atempo did previously.
            // The speed provider is source-relative for this trimmed segment.
            builder.setSpeed(SpeedParameters(object : SpeedProvider {
                override fun getSpeed(timeUs: Long): Float = segment.speed
                override fun getNextSpeedChangeTimeUs(timeUs: Long): Long = C.TIME_UNSET
            }, true))
            // The editor's canonical output is 30 fps. Reject a mismatched
            // delivery rather than silently changing the preview cadence.
            builder.setFrameRate(30)
        }
        return builder.build()
    }

    private data class SourceInfo(
        val width: Int,
        val height: Int,
        val hasAudio: Boolean,
        val frameRate: Int?
    )

    private fun inspectSource(input: File): SourceInfo {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(input.absolutePath)
            var width = 0
            var height = 0
            var hasAudio = false
            var frameRate: Int? = null
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val type = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (type.startsWith("video/") &&
                    format.containsKey(MediaFormat.KEY_WIDTH) &&
                    format.containsKey(MediaFormat.KEY_HEIGHT)) {
                    width = format.getInteger(MediaFormat.KEY_WIDTH)
                    height = format.getInteger(MediaFormat.KEY_HEIGHT)
                    frameRate = if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                        runCatching { format.getInteger(MediaFormat.KEY_FRAME_RATE) }
                            .getOrNull()?.takeIf { it in 1..120 }
                    } else null
                }
                if (type.startsWith("audio/")) hasAudio = true
            }
            require(width > 0 && height > 0) { "Source contains no video track" }
            return SourceInfo(width, height, hasAudio, frameRate)
        } finally {
            extractor.release()
        }
    }

    private fun hasAudioTrack(input: File): Boolean {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(input.absolutePath)
            return (0 until extractor.trackCount).any { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            }
        } finally {
            extractor.release()
        }
    }

    /** Count compressed input video samples; a music-only mix must not lose
     * a frame when the video stream is configured for transmuxing. */
    private fun countVideoSamples(input: File): Long {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(input.absolutePath)
            val track = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("video/") == true
            } ?: throw IllegalArgumentException("Video input has no video track")
            extractor.selectTrack(track)
            var count = 0L
            while (extractor.sampleTime >= 0L) {
                count++
                require(count <= 1000000L) { "Too many input frames" }
                if (!extractor.advance()) break
            }
            require(count > 0) { "Video input contains no frames" }
            return count
        } finally {
            extractor.release()
        }
    }

    /** Overlay one music file while copying video samples; the source audio
     * remains a separate mixed input so it is never silently dropped. */
    private fun startMusicMix(call: MethodCall, reply: MethodChannel.Result) {
        val id = call.argument<String>("id")
        if (id.isNullOrEmpty() || !id.matches(Regex("[A-Za-z0-9_-]+"))) {
            reply.error("ARGUMENT", "Invalid Media3 job id", null)
            return
        }
        if (jobs.isNotEmpty()) {
            reply.error("BUSY", "Another Media3 export is running", null)
            return
        }
        val output = File(context.cacheDir, "tini_media3_$id.mp4")
        try {
            val video = File(requireNotNull(call.argument<String>("videoPath")))
            val audio = File(requireNotNull(call.argument<String>("audioPath")))
            require(video.isFile && video.canRead() && audio.isFile && audio.canRead()) {
                "Music or video source is missing"
            }
            val durationMs = requireNotNull(call.argument<Number>("durationMs")).toLong()
            val startMs = requireNotNull(call.argument<Number>("musicStartMs")).toLong()
            val endMs = requireNotNull(call.argument<Number>("musicEndMs")).toLong()
            val videoVolume = requireNotNull(call.argument<Number>("videoVolume")).toFloat()
            val musicVolume = requireNotNull(call.argument<Number>("musicVolume")).toFloat()
            require(durationMs > 0 && startMs >= 0 && endMs > startMs && endMs <= durationMs &&
                videoVolume.isFinite() && videoVolume in 0f..2f &&
                musicVolume.isFinite() && musicVolume in 0f..2f) {
                "Invalid music range or volume"
            }
            val videoInfo = inspectSource(video)
            require(hasAudioTrack(audio)) { "Music input contains no audio track" }
            if (output.exists() && !output.delete()) {
                throw IllegalStateException("Cannot overwrite Media3 export")
            }
            val originalBuilder = EditedMediaItem.Builder(
                MediaItem.fromUri(Uri.fromFile(video)))
            if (videoInfo.hasAudio) {
                originalBuilder.setEffects(Effects(listOf(
                    GainProcessor(DefaultGainProvider.Builder(videoVolume).build())), emptyList()))
            }
            val original = originalBuilder.build()
            // An originally silent video must not force another audio input.
            // The independent soundtrack provides the output audio instead.
            val baseSequence = if (videoInfo.hasAudio)
                EditedMediaItemSequence.withAudioAndVideoFrom(listOf(original))
                else EditedMediaItemSequence.withVideoFrom(listOf(original))
            val audioItem = MediaItem.Builder().setUri(Uri.fromFile(audio))
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(startMs)
                        .setEndPositionMs(endMs)
                        .build())
                .build()
            val musicItem = EditedMediaItem.Builder(audioItem)
                .setEffects(Effects(listOf(
                    GainProcessor(DefaultGainProvider.Builder(musicVolume).build())), emptyList()))
                .build()
            val musicSequence = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO))
                .apply { if (startMs > 0) addGap(startMs * 1000L) }
                .addItem(musicItem).build()
            val composition = Composition.Builder(listOf(baseSequence, musicSequence))
                // Copy the existing rendered H.264 stream; only audio is mixed.
                .setTransmuxVideo(true)
                .build()
            val builder = Transformer.Builder(context)
                .setEncoderFactory(DefaultEncoderFactory.Builder(context)
                    .setEnableFallback(true)
                    .setEnableFormatFallback(false).build())
            val transformer = builder.addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, result: ExportResult) {
                    finish(id, null)
                }
                override fun onError(composition: Composition, result: ExportResult,
                    exception: ExportException) {
                    finish(id, exception)
                }
            }).build()
            jobs[id] = Job(transformer, output, reply, durationMs,
                countVideoSamples(video), videoInfo.width, videoInfo.height,
                true, exactVideoFrameCount = true)
            transformer.start(composition, output.absolutePath)
        } catch (error: Exception) {
            jobs.remove(id)
            output.delete()
            reply.error("MEDIA3_MIX", error.message ?: "Unable to mix music", null)
        }
    }

    private fun start(call: MethodCall, reply: MethodChannel.Result, timeline: Boolean) {
        val id = call.argument<String>("id")
        if (id.isNullOrEmpty() || !id.matches(Regex("[A-Za-z0-9_-]+"))) {
            reply.error("ARGUMENT", "Invalid Media3 export identifier", null)
            return
        }
        if (jobs.isNotEmpty()) {
            reply.error("BUSY", "A Media3 export is already running", null)
            return
        }
        val output = File(context.cacheDir, "tini_media3_$id.mp4")
        try {
            val segments = if (!timeline) {
                listOf(parseSegment(call.arguments as? Map<*, *>
                    ?: throw IllegalArgumentException("Missing export arguments")))
            } else {
                val entries = call.argument<List<*>>("segments")
                    ?: throw IllegalArgumentException("Missing timeline")
                require(entries.isNotEmpty() && entries.size <= 128) {
                    "A timeline must contain 1..128 clips"
                }
                entries.map { entry ->
                    parseSegment(entry as? Map<*, *>
                        ?: throw IllegalArgumentException("Invalid timeline clip"))
                }
            }
            val expected = if (segments.all { it.endMs != null })
                segments.sumOf { ((it.endMs!! - it.startMs) / it.speed).toLong() }
                else null
            val infos = segments.map { inspectSource(it.input) }
            val commonFrameRate = infos.map { it.frameRate }.distinct()
                .singleOrNull()
            val expectedFrames = if (expected != null && commonFrameRate != null &&
                segments.all { abs(it.speed - 1f) < 0.00001f })
                (expected * commonFrameRate + 500L) / 1000L else null
            val expectedWidth = infos.first().width.takeIf { width ->
                infos.all { it.width == width }
            }
            val expectedHeight = infos.first().height.takeIf { height ->
                infos.all { it.height == height }
            }
            val requireAudio = timeline || segments.indices.any { index ->
                !segments[index].mute && infos[index].hasAudio
            }
            if (output.exists() && !output.delete()) {
                throw IllegalStateException("Cannot replace previous export")
            }
            val builder = Transformer.Builder(context)
                .setEncoderFactory(
                    DefaultEncoderFactory.Builder(context)
                        .setEnableFallback(true)
                        .setEnableFormatFallback(false)
                        .build()
                )
            // Keep source geometry rather than silently downscaling an unsupported
            // output. A rejected encoder returns to Dart's full-effects fallback.
            // Media3 still selects hardware when the device can encode the format.
            if (!timeline && segments.single().colorMatrix == null &&
                (segments.single().startMs > 0L || segments.single().endMs != null)) {
                builder.experimentalSetTrimOptimizationEnabled(true)
            }
            val transformer = builder
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, result: ExportResult) {
                        val job = jobs[id] ?: return
                        if (job.requireVideoTransmux &&
                            result.videoConversionProcess != ExportResult.CONVERSION_PROCESS_TRANSMUXED) {
                            jobs.remove(id)
                            job.output.delete()
                            job.reply.error(
                                "VIDEO_TRANSCODED",
                                "Media3 re-encoded a rendered effects checkpoint; refusing quality loss",
                                result.videoConversionProcess
                            )
                        } else {
                            finish(id, null)
                        }
                    }

                    override fun onError(
                        composition: Composition,
                        result: ExportResult,
                        exception: ExportException
                    ) {
                        finish(id, exception)
                    }
                })
                .build()
            val requestVideoTransmux = timeline &&
                call.argument<Boolean>("transmuxRenderedVideo") == true
            // Transmux is valid only for an effects-complete timeline. Never
            // accept it with speed, colour changes, or muted source segments.
            if (requestVideoTransmux && segments.any { segment ->
                    segment.mute || segment.colorMatrix != null ||
                        abs(segment.speed - 1f) > 0.00001f
                }) {
                throw IllegalArgumentException("Cannot transmux an unrendered effect")
            }
            jobs[id] = Job(transformer, output, reply, expected,
                expectedFrames, expectedWidth, expectedHeight, requireAudio,
                requireVideoTransmux = requestVideoTransmux)
            if (timeline) {
                val sequence = EditedMediaItemSequence.withAudioAndVideoFrom(
                    segments.map(::edited)
                )
                val composition = Composition.Builder(listOf(sequence))
                    .apply { if (requestVideoTransmux) setTransmuxVideo(true) }
                    .build()
                transformer.start(composition, output.absolutePath)
            } else {
                transformer.start(edited(segments.single()), output.absolutePath)
            }
        } catch (error: Exception) {
            jobs.remove(id)
            output.delete()
            reply.error("MEDIA3_START", error.message ?: "Unable to start Media3", null)
        }
    }

    /** Validate the muxed output without decoding it or treating legal B-frames
     * as bad frame order. A detailed FFprobe check is still done by the Dart
     * graph before caching GPU-filter output. */
    private fun verifyOutput(job: Job): String? {
        if (!job.output.isFile || job.output.length() == 0L) return "Empty output file"
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(job.output.absolutePath)
            val duration = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION
            )?.toLongOrNull() ?: return "Missing output duration"
            if (duration <= 0L) return "Invalid output duration"
            job.expectedDurationMs?.let { expected ->
                if (abs(duration - expected) > max(300L, expected / 20L)) {
                    return "Unexpected output duration ($duration vs $expected ms)"
                }
            }
        } finally {
            retriever.release()
        }
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(job.output.absolutePath)
            val tracks = (0 until extractor.trackCount).filter { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("video/") == true
            }
            if (tracks.size != 1) return "Output must contain one video stream"
            if (job.requireAudio && (0 until extractor.trackCount).none { index ->
                    extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                        ?.startsWith("audio/") == true
                }) return "Output lost its audio stream"
            val trackFormat = extractor.getTrackFormat(tracks.single())
            if (!trackFormat.containsKey(MediaFormat.KEY_WIDTH) ||
                !trackFormat.containsKey(MediaFormat.KEY_HEIGHT) ||
                trackFormat.getInteger(MediaFormat.KEY_WIDTH) <= 0 ||
                trackFormat.getInteger(MediaFormat.KEY_HEIGHT) <= 0) {
                return "Invalid output dimensions"
            }
            if ((job.expectedWidth != null &&
                    trackFormat.getInteger(MediaFormat.KEY_WIDTH) != job.expectedWidth) ||
                (job.expectedHeight != null &&
                    trackFormat.getInteger(MediaFormat.KEY_HEIGHT) != job.expectedHeight)) {
                return "Hardware encoder changed video dimensions"
            }
            extractor.selectTrack(tracks.single())
            var frameCount = 0L
            var firstPts = Long.MAX_VALUE
            var lastPts = Long.MIN_VALUE
            while (extractor.sampleTime >= 0L) {
                val presentationTimeUs = extractor.sampleTime
                firstPts = minOf(firstPts, presentationTimeUs)
                lastPts = maxOf(lastPts, presentationTimeUs)
                frameCount++
                if (frameCount > 1000000L) return "Unreasonable output frame count"
                if (!extractor.advance()) break
            }
            if (frameCount < 1L) return "Output contains no video frames"
            // MediaCodec may output legal B-frames with non-monotonic packet
            // presentation timestamps. Validate count and presentation span,
            // not raw packet order, to avoid rejecting a valid encode.
            if (firstPts < 0L || lastPts < firstPts) {
                return "Invalid output frame presentation timestamps"
            }
            job.expectedFrames?.let { expected ->
                val tolerance = if (job.exactVideoFrameCount) 0L
                    else max(3L, expected / 10L)
                if (abs(frameCount - expected) > tolerance) {
                    return "Hardware encoder changed frame count ($frameCount vs $expected)"
                }
            }
        } finally {
            extractor.release()
        }
        return null
    }

    private fun finish(id: String, error: ExportException?) {
        val job = jobs.remove(id) ?: return
        val problem = if (error == null) {
            try { verifyOutput(job) }
            catch (exception: Exception) {
                exception.message ?: "Unable to verify exported media"
            }
        } else {
            error.message ?: "Media3 export failed"
        }
        if (problem == null) {
            job.reply.success(job.output.absolutePath)
        } else {
            job.output.delete()
            job.reply.error("MEDIA3_EXPORT", problem, error?.errorCode)
        }
    }

    fun dispose() {
        if (closed) return
        closed = true
        channel.setMethodCallHandler(null)
        for ((_, job) in jobs) {
            job.transformer.cancel()
            job.output.delete()
            job.reply.error("CLOSED", "Video export interrupted", null)
        }
        jobs.clear()
    }
}
