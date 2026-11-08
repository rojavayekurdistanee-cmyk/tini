
package com.aras.titistar

import android.graphics.Bitmap
import android.graphics.Color
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import com.google.mlkit.vision.segmentation.Segmentation
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.ByteArrayOutputStream
import java.nio.ByteOrder
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject

/** Body tracking for editor effects. Independent of existing cutout and strokes. */
internal class TiniBodyTrackingChannel(engine: FlutterEngine) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    // One-frame preview runs independently from the full-resolution export job.
    private val liveWorker = Executors.newSingleThreadExecutor()
    private val liveBusy = AtomicBoolean(false)
    private var liveRetriever: MediaMetadataRetriever? = null
    private var liveSource: String? = null
    private val liveSegmenter by lazy {
        Segmentation.getClient(SelfieSegmenterOptions.Builder()
            .setDetectorMode(SelfieSegmenterOptions.STREAM_MODE)
            .enableRawSizeMask().build())
    }
    private val livePoseDetector by lazy {
        PoseDetection.getClient(PoseDetectorOptions.Builder()
            .setDetectorMode(PoseDetectorOptions.STREAM_MODE).build())
    }

    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, "titi_star/body_tracking")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "cancel" -> {
                        cancelled.set(true)
                        result.success(null)
                    }
                    "trackFrame" -> {
                        if (!liveBusy.compareAndSet(false, true)) {
                            result.error("BODY_FRAME_BUSY", "Previous preview frame is running", null)
                        } else {
                            liveWorker.execute {
                                try {
                                    val path = requireNotNull(call.argument<String>("path"))
                                    val time = (call.argument<Number>("timeMs") ?: 0).toLong()
                                    val rgb = call.argument<Boolean>("includeRgb") ?: false
                                    val output = trackFrame(path, time, rgb)
                                    main.post { result.success(output) }
                                } catch (error: Exception) {
                                    main.post { result.error("BODY_FRAME_FAILED", error.message ?: "Frame tracking failed", null) }
                                } finally {
                                    liveBusy.set(false)
                                }
                            }
                        }
                    }
                    "createTracking" -> {
                        if (!busy.compareAndSet(false, true)) {
                            result.error("BODY_BUSY", "Body tracking is already running", null)
                        } else {
                            cancelled.set(false)
                            worker.execute {
                                try {
                                    val path = requireNotNull(call.argument<String>("path"))
                                    val target = File(requireNotNull(call.argument<String>("outputDir")))
                                    val start = (call.argument<Number>("startMs") ?: 0).toLong()
                                    val duration = (call.argument<Number>("durationMs") ?: 0).toLong()
                                    val fps = (call.argument<Number>("fps") ?: 12).toInt().coerceIn(4, 15)
                                    val output = createTracking(path, target, start, duration, fps)
                                    main.post { result.success(output) }
                                } catch (error: Exception) {
                                    main.post { result.error("BODY_FAILED", error.message ?: "Body tracking failed", null) }
                                } finally {
                                    busy.set(false)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }


    /** Read only the frame being viewed. No temporary files and no full-clip wait. */
    private fun trackFrame(path: String, timeMs: Long, includeRgb: Boolean): Map<String, Any> {
        if (liveSource != path || liveRetriever == null) {
            liveRetriever?.release()
            liveRetriever = MediaMetadataRetriever().apply { setDataSource(path) }
            liveSource = path
        }
        val retriever = checkNotNull(liveRetriever)
        val videoDuration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            ?.toLong() ?: 0L
        val position = timeMs.coerceIn(0L, max(0L, videoDuration - 1L))
        val frame = retriever.getFrameAtTime(position * 1000L, MediaMetadataRetriever.OPTION_CLOSEST)
            ?: throw IllegalStateException("Could not decode preview frame")
        try {
            // Small inference frame to keep the video player responsive.
            val target = 384
            val width = if (frame.width >= frame.height) target
                else max(1, target * frame.width / frame.height)
            val height = if (frame.height > frame.width) target
                else max(1, target * frame.height / frame.width)
            val scaled = Bitmap.createScaledBitmap(frame, width, height, true)
            try {
                val result = Tasks.await(liveSegmenter.process(InputImage.fromBitmap(scaled, 0)))
                val raw = result.buffer.duplicate().order(ByteOrder.nativeOrder())
                val maskW = result.width
                val maskH = result.height
                val mask = ByteArray(maskW * maskH)
                for (index in mask.indices) {
                    mask[index] = (raw.getFloat().coerceIn(0f, 1f) * 255f).roundToInt().toByte()
                }
                val pose = Tasks.await(livePoseDetector.process(InputImage.fromBitmap(scaled, 0)))
                val joints = HashMap<String, List<Double>>()
                val indices = listOf(
                    "nose" to PoseLandmark.NOSE,
                    "leftShoulder" to PoseLandmark.LEFT_SHOULDER,
                    "rightShoulder" to PoseLandmark.RIGHT_SHOULDER,
                    "leftElbow" to PoseLandmark.LEFT_ELBOW,
                    "rightElbow" to PoseLandmark.RIGHT_ELBOW,
                    "leftWrist" to PoseLandmark.LEFT_WRIST,
                    "rightWrist" to PoseLandmark.RIGHT_WRIST,
                    "leftHip" to PoseLandmark.LEFT_HIP,
                    "rightHip" to PoseLandmark.RIGHT_HIP,
                    "leftKnee" to PoseLandmark.LEFT_KNEE,
                    "rightKnee" to PoseLandmark.RIGHT_KNEE,
                    "leftAnkle" to PoseLandmark.LEFT_ANKLE,
                    "rightAnkle" to PoseLandmark.RIGHT_ANKLE
                )
                for ((name, type) in indices) {
                    val joint = pose.getPoseLandmark(type) ?: continue
                    if (joint.inFrameLikelihood < .5f) continue
                    joints[name] = listOf(joint.position.x.toDouble() / width,
                        joint.position.y.toDouble() / height)
                }
                val output = HashMap<String, Any>()
                output["width"] = maskW
                output["height"] = maskH
                output["mask"] = mask
                output["pose"] = joints
                output["timeMs"] = position
                if (includeRgb) {
                    // Decoded by Flutter only for effects that copy the subject.
                    val resized = if (maskW == width && maskH == height) scaled
                        else Bitmap.createScaledBitmap(scaled, maskW, maskH, true)
                    try {
                        val stream = ByteArrayOutputStream()
                        resized.compress(Bitmap.CompressFormat.JPEG, 80, stream)
                        output["rgb"] = stream.toByteArray()
                    } finally {
                        if (resized !== scaled) resized.recycle()
                    }
                }
                return output
            } finally {
                if (scaled !== frame) scaled.recycle()
            }
        } finally {
            frame.recycle()
        }
    }

    private fun createTracking(path: String, directory: File, startMs: Long,
                               durationMs: Long, fps: Int): Map<String, Any> {
        require(durationMs >= 100L) { "Invalid tracking duration" }
        require(directory.mkdirs() || directory.isDirectory) { "Cannot create tracking directory" }
        val retriever = MediaMetadataRetriever()
        val segmenter = Segmentation.getClient(SelfieSegmenterOptions.Builder()
            .setDetectorMode(SelfieSegmenterOptions.STREAM_MODE)
            .enableRawSizeMask().build())
        val poseDetector = PoseDetection.getClient(PoseDetectorOptions.Builder()
            .setDetectorMode(PoseDetectorOptions.STREAM_MODE).build())
        val allPoses = JSONArray()
        var count = 0
        try {
            retriever.setDataSource(path)
            val total = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLong() ?: 0L
            require(startMs >= 0L && startMs + durationMs <= total + 75L) {
                "Body tracking segment outside video"
            }
            val frames = max(1, (durationMs * fps / 1000.0).roundToInt())
            for (i in 0 until frames) {
                if (cancelled.get()) throw InterruptedException("Body tracking cancelled")
                val timeUs = startMs * 1000L + (i * 1_000_000.0 / fps).toLong()
                val frame = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                    ?: throw IllegalStateException("Could not decode frame $i")
                try {
                    // Masks are compact; pose inference gets a larger frame for
                    // reliable shoulders, wrists and ankles in portrait videos.
                    val maskW = if (frame.width >= frame.height) 512
                        else max(1, 512 * frame.width / frame.height)
                    val maskH = if (frame.height > frame.width) 512
                        else max(1, 512 * frame.height / frame.width)
                    val scaled = Bitmap.createScaledBitmap(frame, maskW, maskH, true)
                    try {
                        val result = Tasks.await(segmenter.process(InputImage.fromBitmap(scaled, 0)))
                        val buffer = result.buffer.duplicate().order(ByteOrder.nativeOrder())
                        val mw = result.width
                        val mh = result.height
                        val pixels = IntArray(mw * mh)
                        for (index in pixels.indices) {
                            val shade = (buffer.getFloat().coerceIn(0f, 1f) * 255).roundToInt()
                            pixels[index] = Color.rgb(shade, shade, shade)
                        }
                        val nativeMask = Bitmap.createBitmap(mw, mh, Bitmap.Config.ARGB_8888)
                        try {
                            nativeMask.setPixels(pixels, 0, mw, 0, 0, mw, mh)
                            val mask = Bitmap.createScaledBitmap(nativeMask, maskW, maskH, true)
                            try {
                                FileOutputStream(File(directory,
                                    String.format(Locale.US, "mask_%06d.png", i))).use {
                                    mask.compress(Bitmap.CompressFormat.PNG, 100, it)
                                }
                            } finally {
                                if (mask !== nativeMask) mask.recycle()
                            }
                        } finally { nativeMask.recycle() }
                    } finally { if (scaled !== frame) scaled.recycle() }

                    val poseW = if (frame.width >= frame.height) 720
                        else max(1, 720 * frame.width / frame.height)
                    val poseH = if (frame.height > frame.width) 720
                        else max(1, 720 * frame.height / frame.width)
                    val poseBitmap = Bitmap.createScaledBitmap(frame, poseW, poseH, true)
                    try {
                        val pose = Tasks.await(poseDetector.process(
                            InputImage.fromBitmap(poseBitmap, 0)))
                        val json = JSONObject()
                        val landmarks = listOf(
                            "nose" to PoseLandmark.NOSE,
                            "leftShoulder" to PoseLandmark.LEFT_SHOULDER,
                            "rightShoulder" to PoseLandmark.RIGHT_SHOULDER,
                            "leftElbow" to PoseLandmark.LEFT_ELBOW,
                            "rightElbow" to PoseLandmark.RIGHT_ELBOW,
                            "leftWrist" to PoseLandmark.LEFT_WRIST,
                            "rightWrist" to PoseLandmark.RIGHT_WRIST,
                            "leftHip" to PoseLandmark.LEFT_HIP,
                            "rightHip" to PoseLandmark.RIGHT_HIP,
                            "leftKnee" to PoseLandmark.LEFT_KNEE,
                            "rightKnee" to PoseLandmark.RIGHT_KNEE,
                            "leftAnkle" to PoseLandmark.LEFT_ANKLE,
                            "rightAnkle" to PoseLandmark.RIGHT_ANKLE
                        )
                        for ((name, type) in landmarks) {
                            val landmark = pose.getPoseLandmark(type) ?: continue
                            if (landmark.inFrameLikelihood < 0.5f) continue
                            json.put(name, JSONArray()
                                .put(landmark.position.x / poseW.toDouble())
                                .put(landmark.position.y / poseH.toDouble()))
                        }
                        allPoses.put(json)
                    } finally { if (poseBitmap !== frame) poseBitmap.recycle() }
                } finally { frame.recycle() }
                count++
            }
            File(directory, "poses.json").writeText(allPoses.toString(), Charsets.UTF_8)
            return mapOf("directory" to directory.absolutePath, "fps" to fps,
                "count" to count)
        } catch (e: Exception) {
            directory.deleteRecursively()
            throw e
        } finally {
            try { segmenter.close() } catch (_: Exception) {}
            try { poseDetector.close() } catch (_: Exception) {}
            try { retriever.release() } catch (_: Exception) {}
        }
    }
}
