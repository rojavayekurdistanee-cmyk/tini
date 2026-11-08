package com.aras.titistar

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.min

/**
 * Offline, ordered GPU export: hardware decoder -> existing retouch shaders -> hardware AVC
 * encoder. Audio packets keep their source timestamps and are copied without an additional audio
 * encode or per-clip AAC priming delay. There are no PNG batches or per-frame Flutter messages in
 * this path.
 */
class TiniRetouchExportChannel(engine: FlutterEngine) {
    private val main = Handler(Looper.getMainLooper())
    private val channel =
        MethodChannel(engine.dartExecutor.binaryMessenger, "titi_star/retouch_export")
    private val worker = Executors.newSingleThreadExecutor()
    private val jobs = ConcurrentHashMap<String, Job>()
    @Volatile private var closed = false

    init {
        channel.setMethodCallHandler(::handle)
    }

    private class Job(val id: String) {
        val cancelled = AtomicBoolean(false)
        @Volatile var frames = 0
        @Volatile var totalFrames = 0
    }

    private data class Region(val start: Long, val end: Long, val smooth: Float, val teeth: Float)

    private class Cancelled : RuntimeException("GPU export cancelled")

    private class BaselineRequired(message: String) : RuntimeException(message)

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.error("CLOSED", "Export channel is closed", null)
            return
        }
        val id = call.argument<String>("id")
        if (id.isNullOrBlank()) {
            result.error("ARGUMENT", "Export id is missing", null)
            return
        }
        when (call.method) {
            "videoEncoder" -> {
                val width = call.argument<Number>("width")?.toInt() ?: 0
                val height = call.argument<Number>("height")?.toInt() ?: 0
                if (width < 2 || height < 2 || width % 2 != 0 || height % 2 != 0) {
                    result.error("ARGUMENT", "Invalid encoder dimensions", null)
                    return
                }
                Thread {
                    val value = TiniHardwareVideoCodec.probe(width, height)
                    main.post { result.success(value) }
                }.start()
            }
            "cancel" -> {
                jobs[id]?.cancelled?.set(true)
                result.success(null)
            }
            "status" -> {
                val job = jobs[id]
                result.success(
                    if (job == null) null
                    else mapOf("frames" to job.frames, "totalFrames" to job.totalFrames)
                )
            }
            "render" -> {
                val job = Job(id)
                if (jobs.putIfAbsent(id, job) != null) {
                    result.error("BUSY", "This export is already running", null)
                    return
                }
                // Capture arguments on the platform thread. Only immutable
                // primitives and the parsed region list enter the worker.
                try {
                    val input = requireNotNull(call.argument<String>("input"))
                    val output = requireNotNull(call.argument<String>("output"))
                    val width = requireNotNull(call.argument<Number>("width")).toInt()
                    val height = requireNotNull(call.argument<Number>("height")).toInt()
                    val duration = requireNotNull(call.argument<Number>("durationMs")).toLong()
                    val start = call.argument<Number>("sourceStartMs")?.toLong() ?: 0L
                    val muted = call.argument<Boolean>("muted") == true
                    val smooth = amount(call.argument<Number>("smooth"))
                    val teeth = amount(call.argument<Number>("teeth"))
                    val regions =
                        (call.argument<List<Map<*, *>>>("regions") ?: emptyList()).map {
                            val begin = (it["startMs"] as Number).toLong()
                            val end = (it["endMs"] as Number).toLong()
                            require(begin >= 0 && end > begin)
                            Region(
                                begin,
                                end,
                                amount(it["smooth"] as? Number),
                                amount(it["teeth"] as? Number),
                            )
                        }
                    require(width >= 2 && height >= 2 && width % 2 == 0 && height % 2 == 0)
                    require(duration > 0 && start >= 0)
                    require(
                        File(input).isFile &&
                            File(input).canonicalPath != File(output).canonicalPath
                    )
                    worker.execute {
                        try {
                            val value =
                                export(
                                    job,
                                    input,
                                    output,
                                    width,
                                    height,
                                    start,
                                    duration,
                                    muted,
                                    smooth,
                                    teeth,
                                    regions,
                                )
                            main.post { result.success(value) }
                        } catch (problem: Throwable) {
                            File(output).delete()
                            main.post {
                                result.error(
                                    if (problem is Cancelled || closed || job.cancelled.get())
                                        "CANCELLED"
                                    else if (problem is BaselineRequired) "BASELINE_REQUIRED"
                                    else "GPU_EXPORT",
                                    problem.message ?: problem.javaClass.simpleName,
                                    null,
                                )
                            }
                        } finally {
                            jobs.remove(id, job)
                        }
                    }
                } catch (problem: Exception) {
                    jobs.remove(id, job)
                    result.error("ARGUMENT", problem.message ?: "Invalid export arguments", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun amount(value: Number?): Float {
        val f = value?.toFloat() ?: 0f
        require(f.isFinite())
        return f.coerceIn(0f, 1f)
    }

    fun dispose() {
        if (closed) return
        closed = true
        channel.setMethodCallHandler(null)
        jobs.values.forEach { it.cancelled.set(true) }
        worker.shutdown()
    }

    private fun check(job: Job) {
        if (closed || job.cancelled.get()) throw Cancelled()
    }

    private fun codec(width: Int, height: Int, frameRate: Int): MediaCodecInfo {
        val candidates =
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { info ->
                info.isEncoder &&
                    info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_AVC, true) } &&
                    (if (Build.VERSION.SDK_INT >= 29) info.isHardwareAccelerated
                    else
                        !info.name.startsWith("OMX.google.") &&
                            !info.name.startsWith("c2.android."))
            }
        return candidates.firstOrNull { info ->
            try {
                val caps = info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
                caps.colorFormats.contains(MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface) &&
                    caps.videoCapabilities.areSizeAndRateSupported(
                        width,
                        height,
                        frameRate.toDouble(),
                    )
            } catch (_: Exception) {
                false
            }
        }
            ?: throw BaselineRequired(
                "No hardware AVC encoder supports ${width}x$height at $frameRate fps"
            )
    }

    private fun track(extractor: MediaExtractor, prefix: String): Int =
        (0 until extractor.trackCount).firstOrNull {
            extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith(prefix) == true
        } ?: -1

    private fun export(
        job: Job,
        input: String,
        output: String,
        width: Int,
        height: Int,
        sourceStartMs: Long,
        durationMs: Long,
        muted: Boolean,
        smooth: Float,
        teeth: Float,
        regions: List<Region>,
    ): Map<String, Any> {
        val startedAt = SystemClock.elapsedRealtime()
        check(job)
        val video = MediaExtractor()
        var audio: MediaExtractor? = null
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var encoderSurface: android.view.Surface? = null
        var gl: TiniRetouchExportGl? = null
        var muxer: MediaMuxer? = null
        var decoderStarted = false
        var encoderStarted = false
        var muxerStarted = false
        var success = false
        var faceFrames = 0
        val startUs = Math.multiplyExact(sourceStartMs, 1000L)
        val durationUs = Math.multiplyExact(durationMs, 1000L)
        val endUs = Math.addExact(startUs, durationUs)
        try {
            video.setDataSource(input)
            val videoTrack = track(video, "video/")
            require(videoTrack >= 0) { "Source has no video track" }
            val sourceFormat = video.getTrackFormat(videoTrack)
            if (
                Build.VERSION.SDK_INT >= 24 &&
                    sourceFormat.containsKey(MediaFormat.KEY_COLOR_TRANSFER)
            ) {
                val transfer = sourceFormat.getInteger(MediaFormat.KEY_COLOR_TRANSFER)
                if (
                    transfer == MediaFormat.COLOR_TRANSFER_ST2084 ||
                        transfer == MediaFormat.COLOR_TRANSFER_HLG
                )
                    throw BaselineRequired("HDR source requires baseline SDR normalization")
            }
            video.selectTrack(videoTrack)
            video.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val frameRate =
                (if (sourceFormat.containsKey(MediaFormat.KEY_FRAME_RATE))
                        try {
                            sourceFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
                        } catch (_: ClassCastException) {
                            sourceFormat.getFloat(MediaFormat.KEY_FRAME_RATE).toInt()
                        }
                    else 30)
                    .coerceAtLeast(1)
            job.totalFrames = min(Int.MAX_VALUE.toLong(), durationMs * frameRate / 1000L).toInt()
            val codecInfo = codec(width, height, frameRate)
            val caps = codecInfo.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
            val sourceBitrate =
                if (sourceFormat.containsKey(MediaFormat.KEY_BIT_RATE))
                    sourceFormat.getInteger(MediaFormat.KEY_BIT_RATE)
                else 0
            val qualityBitrate =
                (width.toLong() * height * frameRate / 5)
                    .coerceAtMost(Int.MAX_VALUE.toLong())
                    .toInt()
            val bitrate =
                caps.videoCapabilities.bitrateRange.clamp(
                    max(4_000_000, max(sourceBitrate, qualityBitrate))
                )
            val targetFormat =
                MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
                    setInteger(
                        MediaFormat.KEY_COLOR_FORMAT,
                        MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
                    )
                    setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                    setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
                    setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                    for (key in
                        listOf(
                            MediaFormat.KEY_COLOR_STANDARD,
                            MediaFormat.KEY_COLOR_RANGE,
                            MediaFormat.KEY_COLOR_TRANSFER,
                        )) {
                        if (sourceFormat.containsKey(key))
                            setInteger(key, sourceFormat.getInteger(key))
                    }
                    if (
                        caps.encoderCapabilities.isBitrateModeSupported(
                            MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR
                        )
                    )
                        setInteger(
                            MediaFormat.KEY_BITRATE_MODE,
                            MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR,
                        )
                    if (
                        caps.profileLevels.any {
                            it.profile == MediaCodecInfo.CodecProfileLevel.AVCProfileHigh
                        }
                    )
                        setInteger(
                            MediaFormat.KEY_PROFILE,
                            MediaCodecInfo.CodecProfileLevel.AVCProfileHigh,
                        )
                    if (Build.VERSION.SDK_INT >= 29) setInteger("max-bframes", 0)
                }
            encoder = MediaCodec.createByCodecName(codecInfo.name)
            encoder.configure(targetFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoderSurface = encoder.createInputSurface()
            encoder.start()
            encoderStarted = true
            gl =
                TiniRetouchExportGl(encoderSurface, width, height) { closed || job.cancelled.get() }
            val mime = requireNotNull(sourceFormat.getString(MediaFormat.KEY_MIME))
            decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(sourceFormat, gl.decoderSurface, null, 0)
            decoder.start()
            decoderStarted = true
            val destination = File(output)
            destination.parentFile?.mkdirs()
            if (destination.exists())
                require(destination.delete()) { "Cannot replace export output" }
            muxer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            // Rotation is consumed by the decoder SurfaceTexture transform and
            // baked into upright pixels. Do not attach source rotation again.
            muxer.setOrientationHint(0)
            var audioMuxTrack = -1
            var audioFormat: MediaFormat? = null
            if (!muted) {
                val candidate = MediaExtractor()
                audio = candidate
                candidate.setDataSource(input)
                val audioTrack = track(candidate, "audio/")
                if (audioTrack >= 0) {
                    candidate.selectTrack(audioTrack)
                    candidate.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                    audioFormat = candidate.getTrackFormat(audioTrack)
                    val audioMime = audioFormat.getString(MediaFormat.KEY_MIME)
                    if (audioMime !in setOf("audio/mp4a-latm", "audio/3gpp", "audio/amr-wb"))
                        throw BaselineRequired(
                            "Source audio requires normalization before MP4 packet copying"
                        )
                    if (candidate.sampleTime >= 0) audioMuxTrack = muxer.addTrack(audioFormat)
                } else {
                    candidate.release()
                    audio = null
                }
            }
            var videoMuxTrack = -1
            var inputDone = false
            var decoderDone = false
            var encoderDone = false
            var lastVideoPts = -1L
            var lastEncoderPts = -1L
            var lastProgress = SystemClock.elapsedRealtime()
            val decodeInfo = MediaCodec.BufferInfo()
            val encodeInfo = MediaCodec.BufferInfo()

            var audioBuffer: ByteBuffer? = null
            fun writeAudioUntil(untilSourceUs: Long) {
                val reader = audio ?: return
                if (audioMuxTrack < 0) return
                var buffer: ByteBuffer =
                    audioBuffer
                        ?: run {
                            val format = requireNotNull(audioFormat)
                            val suggested =
                                if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE))
                                    format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                                else 0
                            require(suggested <= 16 * 1024 * 1024) {
                                "Audio buffer exceeds safety limit"
                            }
                            ByteBuffer.allocateDirect(max(256 * 1024, suggested))
                        }
                val info = MediaCodec.BufferInfo()
                while (true) {
                    check(job)
                    val pts = reader.sampleTime
                    if (pts < 0 || pts >= min(untilSourceUs, endUs)) break
                    if (pts >= startUs) {
                        val size =
                            if (Build.VERSION.SDK_INT >= 28) reader.sampleSize
                            else buffer.capacity().toLong()
                        require(size <= 16 * 1024 * 1024) { "Audio sample exceeds safety limit" }
                        if (size > buffer.capacity())
                            buffer = ByteBuffer.allocateDirect(size.toInt())
                        buffer.clear()
                        val n = reader.readSampleData(buffer, 0)
                        if (n < 0) break
                        require(reader.sampleFlags and MediaExtractor.SAMPLE_FLAG_ENCRYPTED == 0) {
                            "Encrypted audio cannot be copied"
                        }
                        info.set(
                            0,
                            n,
                            pts - startUs,
                            reader.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC,
                        )
                        muxer.writeSampleData(audioMuxTrack, buffer, info)
                    }
                    if (!reader.advance()) break
                }
                audioBuffer = buffer
            }

            fun drainEncoder() {
                while (true) {
                    check(job)
                    val index = encoder.dequeueOutputBuffer(encodeInfo, 0)
                    when {
                        index == MediaCodec.INFO_TRY_AGAIN_LATER -> return
                        index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            check(!muxerStarted) { "Encoder changed output format twice" }
                            videoMuxTrack = muxer.addTrack(encoder.outputFormat)
                            muxer.start()
                            muxerStarted = true
                            lastProgress = SystemClock.elapsedRealtime()
                        }
                        index >= 0 -> {
                            try {
                                if (
                                    encodeInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0 &&
                                        encodeInfo.size > 0
                                ) {
                                    check(muxerStarted) { "Video arrived before its format" }
                                    check(encodeInfo.presentationTimeUs >= lastEncoderPts) {
                                        "Non-monotonic video timestamp"
                                    }
                                    lastEncoderPts = encodeInfo.presentationTimeUs
                                    val buffer = requireNotNull(encoder.getOutputBuffer(index))
                                    buffer.position(encodeInfo.offset)
                                    buffer.limit(encodeInfo.offset + encodeInfo.size)
                                    muxer.writeSampleData(videoMuxTrack, buffer, encodeInfo)
                                    writeAudioUntil(
                                        startUs +
                                            encodeInfo.presentationTimeUs +
                                            1_000_000L / frameRate
                                    )
                                }
                                if (encodeInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0)
                                    encoderDone = true
                                lastProgress = SystemClock.elapsedRealtime()
                            } finally {
                                encoder.releaseOutputBuffer(index, false)
                            }
                        }
                    }
                }
            }

            while (!encoderDone) {
                check(job)
                drainEncoder()
                if (!inputDone) {
                    val index = decoder.dequeueInputBuffer(5_000)
                    if (index >= 0) {
                        val buffer = requireNotNull(decoder.getInputBuffer(index))
                        buffer.clear()
                        val pts = video.sampleTime
                        // Feed a short decode preroll beyond the requested end
                        // so reordered B-frames before the cut are not lost.
                        val n =
                            if (pts < 0 || pts > endUs + 2_000_000L) -1
                            else video.readSampleData(buffer, 0)
                        if (n < 0) {
                            decoder.queueInputBuffer(
                                index,
                                0,
                                0,
                                0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(index, 0, n, pts, 0)
                            video.advance()
                        }
                    }
                }
                if (!decoderDone) {
                    val index = decoder.dequeueOutputBuffer(decodeInfo, 5_000)
                    if (index >= 0) {
                        val eos = decodeInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        val pts = decodeInfo.presentationTimeUs
                        val render = decodeInfo.size > 0 && pts >= startUs && pts < endUs
                        decoder.releaseOutputBuffer(index, render)
                        if (render) {
                            val localPts = pts - startUs
                            check(localPts > lastVideoPts) {
                                "Decoder produced duplicate or reversed timestamps"
                            }
                            val atMs = localPts / 1000L
                            val region = regions.firstOrNull { atMs >= it.start && atMs < it.end }
                            val amounts =
                                if (regions.isEmpty()) Pair(smooth, teeth)
                                else Pair(region?.smooth ?: 0f, region?.teeth ?: 0f)
                            gl.awaitFrameAndDraw(localPts, amounts.first, amounts.second)
                            drainEncoder()
                            lastVideoPts = localPts
                            job.frames++
                            if (gl.faceCount > 0) faceFrames++
                        }
                        if (eos) {
                            decoderDone = true
                            encoder.signalEndOfInputStream()
                        }
                        lastProgress = SystemClock.elapsedRealtime()
                    } else if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        lastProgress = SystemClock.elapsedRealtime()
                    }
                }
                if (SystemClock.elapsedRealtime() - lastProgress > 30_000L)
                    throw IllegalStateException("Hardware video codec stopped producing frames")
            }
            check(job.frames > 0 && muxerStarted) { "No video frames were encoded" }
            writeAudioUntil(endUs)
            check(job)
            muxer.stop()
            muxerStarted = false
            check(File(output).length() > 0) { "Hardware encoder produced an empty file" }
            success = true
            val elapsedMs = SystemClock.elapsedRealtime() - startedAt
            Log.i(
                "TiniExport",
                "GPU export frames=${job.frames} elapsedMs=$elapsedMs encoder=${codecInfo.name} bitrate=$bitrate",
            )
            return mapOf(
                "path" to output,
                "frames" to job.frames,
                "faceFrames" to faceFrames,
                "width" to width,
                "height" to height,
                "durationMs" to durationMs,
                "elapsedMs" to elapsedMs,
                "encoder" to codecInfo.name,
                "bitrate" to bitrate,
            )
        } finally {
            // Release every codec, extractor, surface and EGL object on errors,
            // cancellations and successful completion alike.
            try {
                if (decoderStarted) decoder?.stop()
            } catch (_: Exception) {}
            try {
                decoder?.release()
            } catch (_: Exception) {}
            try {
                gl?.close()
            } catch (_: Exception) {}
            try {
                if (encoderStarted) encoder?.stop()
            } catch (_: Exception) {}
            try {
                encoder?.release()
            } catch (_: Exception) {}
            try {
                encoderSurface?.release()
            } catch (_: Exception) {}
            try {
                if (muxerStarted) muxer?.stop()
            } catch (_: Exception) {}
            try {
                muxer?.release()
            } catch (_: Exception) {}
            try {
                video.release()
            } catch (_: Exception) {}
            try {
                audio?.release()
            } catch (_: Exception) {}
            if (!success) File(output).delete()
        }
    }
}
