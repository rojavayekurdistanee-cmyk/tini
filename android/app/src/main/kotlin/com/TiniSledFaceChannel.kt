
package com.aras.titistar

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Isolated ML Kit face sampling for the Tini sled effect.
 * One detector/retriever per Flutter engine; bounded worker queue, no FFmpeg.
 * Source frame decoding never happens on the UI thread.
 */
class TiniSledFaceChannel(engine: FlutterEngine) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val detector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setMinFaceSize(0.08f)
            .build()
    )
    // Detail landmarks are calculated ONLY for AR face accessories.
    // The legacy sled detector and its original speed remain unchanged.
    private val poseDetector by lazy {
        FaceDetection.getClient(
            FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                .setMinFaceSize(0.08f)
                .build()
        )
    }
    private var retriever: MediaMetadataRetriever? = null
    private var currentSource: String? = null
    // Bounded per-source cache: re-entering preview / scrubbing must not
    // decode the same frame and invoke ML Kit again. All calls use `worker`.
    private val faceCache = android.util.LruCache<String, Map<String, Double>>(160)

    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, "titi_star/sled_face")
            .setMethodCallHandler { call, reply ->
                when (call.method) {
                    "detect", "detectPose" -> {
                        val withPose = call.method == "detectPose"
                        val path = call.argument<String>("path")
                        val timeMs = call.argument<Int>("timeMs") ?: 0
                        if (path.isNullOrBlank()) {
                            reply.error("INVALID_PATH", "Missing source file", null)
                        } else {
                            worker.execute {
                                try {
                                    val data = findFace(path, timeMs.toLong(), withPose)
                                    main.post { reply.success(data) }
                                } catch (error: Exception) {
                                    main.post {
                                        reply.error("SLED_FACE", error.message, null)
                                    }
                                }
                            }
                        }
                    }
                    "detectPoseBatch" -> {
                        val path = call.argument<String>("path")
                        val requested = call.argument<List<Int>>("timesMs")
                        if (path.isNullOrBlank() || requested.isNullOrEmpty() ||
                            requested.size > 16) {
                            reply.error("INVALID_POSE_BATCH", "Expected a path and 1..16 timesMs", null)
                        } else {
                            worker.execute {
                                try {
                                    val results = mutableListOf<Map<String, Double>>()
                                    for (timeMs in requested) {
                                        val sample = findFace(path, timeMs.toLong(), true)
                                        if (sample != null) {
                                            results.add(sample + ("timeMs" to timeMs.toDouble()))
                                        }
                                    }
                                    main.post { reply.success(results) }
                                } catch (error: Exception) {
                                    main.post { reply.error("FACE_POSE_BATCH", error.message, null) }
                                }
                            }
                        }
                    }
                    "reset" -> {
                        worker.execute { closeSource() }
                        reply.success(true)
                    }
                    else -> reply.notImplemented()
                }
            }
    }

    private fun source(path: String): MediaMetadataRetriever {
        if (path == currentSource && retriever != null) return retriever!!
        closeSource()
        val next = MediaMetadataRetriever()
        try {
            next.setDataSource(path)
        } catch (error: Exception) {
            next.release()
            throw error
        }
        currentSource = path
        retriever = next
        return next
    }

    private fun findFace(path: String, timeMs: Long,
                         withPose: Boolean = false): Map<String, Double>? {
        val video = source(path)
        val cacheKey = "${if (withPose) "pose" else "sled"}:$timeMs"
        faceCache.get(cacheKey)?.let { return it }
        val timeUs = timeMs.coerceAtLeast(0L) * 1000L
        val frame: Bitmap = if (Build.VERSION.SDK_INT >= 27) {
            val w = video.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 640
            val h = video.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 640
            val scale = 384.0 / maxOf(w, h, 1)
            video.getScaledFrameAtTime(timeUs,
                MediaMetadataRetriever.OPTION_CLOSEST,
                maxOf(32, (w * scale).toInt()),
                maxOf(32, (h * scale).toInt())) ?: return null
        } else {
            val original = video.getFrameAtTime(timeUs,
                MediaMetadataRetriever.OPTION_CLOSEST) ?: return null
            val scale = 384.0 / maxOf(original.width, original.height, 1)
            val w = maxOf(32, (original.width * scale).toInt())
            val h = maxOf(32, (original.height * scale).toInt())
            val resized = Bitmap.createScaledBitmap(original, w, h, true)
            if (resized !== original) original.recycle()
            resized
        }
        try {
            val selectedDetector = if (withPose) poseDetector else detector
            val faces = Tasks.await(selectedDetector.process(InputImage.fromBitmap(frame, 0)),
                2300, TimeUnit.MILLISECONDS)
            val best = faces.maxByOrNull {
                it.boundingBox.width().toLong() * it.boundingBox.height().toLong()
            } ?: return null
            val box = best.boundingBox
            val w = frame.width.toDouble()
            val h = frame.height.toDouble()
            val result = mutableMapOf(
                "cx" to (((box.left + box.right) / 2.0) / w).coerceIn(0.0, 1.0),
                "cy" to (((box.top + box.bottom) / 2.0) / h).coerceIn(0.0, 1.0),
                "width" to (box.width() / w).coerceIn(0.0, 1.0),
                "height" to (box.height() / h).coerceIn(0.0, 1.0)
            )
            if (withPose) {
                result["roll"] = best.headEulerAngleZ.toDouble()
                result["yaw"] = best.headEulerAngleY.toDouble()
                result["pitch"] = best.headEulerAngleX.toDouble()
                // The original detect method remains unaffected. Landmark
                // coordinates are returned only for face-scene attachments.
                fun landmark(kind: Int, x: String, y: String) {
                    val point = best.getLandmark(kind)?.position ?: return
                    result[x] = (point.x.toDouble() / w).coerceIn(0.0, 1.0)
                    result[y] = (point.y.toDouble() / h).coerceIn(0.0, 1.0)
                }
                landmark(FaceLandmark.NOSE_BASE, "nx", "ny")
                landmark(FaceLandmark.LEFT_EYE, "lex", "ley")
                landmark(FaceLandmark.RIGHT_EYE, "rex", "rey")
                landmark(FaceLandmark.LEFT_EAR, "lax", "lay")
                landmark(FaceLandmark.RIGHT_EAR, "rax", "ray")
                landmark(FaceLandmark.MOUTH_BOTTOM, "mx", "my")
            }
            faceCache.put(cacheKey, result)
            return result
        } finally {
            frame.recycle()
        }
    }

    private fun closeSource() {
        try { retriever?.release() } catch (_: Exception) { }
        retriever = null
        currentSource = null
        faceCache.evictAll()
    }
}
