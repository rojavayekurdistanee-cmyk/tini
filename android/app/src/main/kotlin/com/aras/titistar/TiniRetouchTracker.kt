package com.aras.titistar

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Path
import android.graphics.PointF
import android.graphics.Rect
import android.graphics.Region
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceContour
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.*

/**
 * At most one inference in flight. It consumes the existing decoder's GPU readback, not another
 * MediaMetadataRetriever/decoder or PNG/JPEG files.
 */
internal class TiniRetouchTracker(
    private val deliver: (List<Bitmap>, Int, Long, Long, List<TiniRetouchRegion>) -> Unit,
    private val failure: (String) -> Unit,
) {
    private val executor = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val cleaned = AtomicBoolean(false)
    private val detector =
        FaceDetection.getClient(
            FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setContourMode(FaceDetectorOptions.CONTOUR_MODE_ALL)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                .setMinFaceSize(.06f)
                .build()
        )
    private var bitmap: Bitmap? = null
    val isBusy: Boolean
        get() = busy.get()

    fun acquire(): Boolean = !closed.get() && busy.compareAndSet(false, true)

    fun abandon() {
        busy.set(false)
        if (closed.get() && !cleaned.get()) executor.execute { finish() }
    }

    fun offer(
        pixels: IntArray,
        width: Int,
        height: Int,
        sourceWidth: Int,
        generation: Long,
        capturedAt: Long,
    ) {
        if (closed.get()) {
            executor.execute { finish() }
            return
        }
        executor.execute {
            if (closed.get()) {
                finish()
                return@execute
            }
            try {
                var image = bitmap
                if (image == null || image.width != width || image.height != height) {
                    image?.recycle()
                    image = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    bitmap = image
                }
                image!!.setPixels(pixels, 0, width, 0, 0, width, height)
                detector
                    .process(InputImage.fromBitmap(image, 0))
                    .addOnSuccessListener(executor) { faces ->
                        if (!closed.get()) {
                            val selected =
                                faces
                                    .sortedByDescending {
                                        it.boundingBox.width() * it.boundingBox.height()
                                    }
                                    .take(4)
                            val masks =
                                selected.map { createMask(listOf(it), width, height, sourceWidth) }
                            if (!closed.get())
                                deliver(
                                    masks,
                                    selected.size,
                                    generation,
                                    capturedAt,
                                    selected.map { motionRegion(it, width, height) },
                                )
                            else masks.forEach { it.recycle() }
                        }
                    }
                    .addOnFailureListener(executor) { problem ->
                        if (!closed.get()) failure("تعذر كشف الوجه: ${problem.message}")
                    }
                    .addOnCompleteListener(executor) { finish() }
            } catch (problem: Exception) {
                if (!closed.get()) failure("تعذر كشف الوجه: ${problem.message}")
                finish()
            }
        }
    }

    private fun finish() {
        busy.set(false)
        if (closed.get() && cleaned.compareAndSet(false, true)) {
            bitmap?.recycle()
            bitmap = null
            detector.close()
            executor.shutdown()
        }
    }

    fun close() {
        if (closed.compareAndSet(false, true) && !busy.get()) executor.execute { finish() }
    }

    private fun ramp(value: Float, low: Float, high: Float): Float {
        val t = ((value - low) / (high - low)).coerceIn(0f, 1f)
        return t * t * (3f - 2f * t)
    }

    private fun points(face: Face, type: Int): List<PointF> =
        face.getContour(type)?.points ?: emptyList()

    private fun region(points: List<PointF>, width: Int, height: Int): Region {
        if (points.size < 3) return Region()
        val path = Path()
        path.moveTo(points[0].x, points[0].y)
        points.drop(1).forEach { path.lineTo(it.x, it.y) }
        path.close()
        return Region().apply { setPath(path, Region(0, 0, width, height)) }
    }

    private fun eye(face: Face, type: Int, landmark: Int): List<PointF> {
        val contour = points(face, type)
        if (contour.isNotEmpty()) return contour
        val point = face.getLandmark(landmark)?.position ?: return emptyList()
        return (0 until 16).map { i ->
            PointF(
                point.x + face.boundingBox.width() * .09f * cos(i * PI / 8).toFloat(),
                point.y + face.boundingBox.height() * .045f * sin(i * PI / 8).toFloat(),
            )
        }
    }

    private fun distance(x: Float, y: Float, polygon: List<PointF>): Float {
        var best = Float.POSITIVE_INFINITY
        var previous = polygon.lastOrNull() ?: return best
        polygon.forEach { next ->
            val dx = next.x - previous.x
            val dy = next.y - previous.y
            val length = dx * dx + dy * dy
            val t =
                if (length <= 0) 0f
                else (((x - previous.x) * dx + (y - previous.y) * dy) / length).coerceIn(0f, 1f)
            best = min(best, hypot(x - previous.x - dx * t, y - previous.y - dy * t))
            previous = next
        }
        return best
    }

    private fun motionRegion(face: Face, width: Int, height: Int): TiniRetouchRegion {
        val b = face.boundingBox
        val mouth =
            points(face, FaceContour.UPPER_LIP_BOTTOM) + points(face, FaceContour.LOWER_LIP_TOP)
        val left = if (mouth.isEmpty()) b.left + b.width() * .3f else mouth.minOf { it.x }
        val right = if (mouth.isEmpty()) b.left + b.width() * .7f else mouth.maxOf { it.x }
        val top = if (mouth.isEmpty()) b.top + b.height() * .65f else mouth.minOf { it.y }
        val bottom = if (mouth.isEmpty()) b.top + b.height() * .85f else mouth.maxOf { it.y }
        return TiniRetouchRegion(
            b.left.toFloat() / width,
            b.top.toFloat() / height,
            b.right.toFloat() / width,
            b.bottom.toFloat() / height,
            left / width,
            top / height,
            right / width,
            bottom / height,
        )
    }

    private fun createMask(faces: List<Face>, width: Int, height: Int, sourceWidth: Int): Bitmap {
        val pixels = IntArray(width * height) { Color.BLACK }
        faces.forEach { face ->
            val box = face.boundingBox
            if (box.width() < 8 || box.height() < 8) return@forEach
            val outline = points(face, FaceContour.FACE)
            val outlineRegion = region(outline, width, height)
            val leftEye = eye(face, FaceContour.LEFT_EYE, FaceLandmark.LEFT_EYE)
            val rightEye = eye(face, FaceContour.RIGHT_EYE, FaceLandmark.RIGHT_EYE)
            val eyes =
                listOf(leftEye, rightEye).map { p ->
                    val bounds =
                        if (p.isEmpty()) Rect()
                        else
                            Rect(
                                floor(p.minOf { it.x } - box.width() * .025f).toInt(),
                                floor(p.minOf { it.y } - box.width() * .025f).toInt(),
                                ceil(p.maxOf { it.x } + box.width() * .025f).toInt(),
                                ceil(p.maxOf { it.y } + box.width() * .025f).toInt(),
                            )
                    Triple(p, region(p, width, height), bounds)
                }
            val upper = points(face, FaceContour.UPPER_LIP_BOTTOM).sortedBy { it.x }
            val lower = points(face, FaceContour.LOWER_LIP_TOP).sortedByDescending { it.x }
            val mouth =
                if (
                    upper.size >= 3 &&
                        lower.size >= 3 &&
                        lower.map { it.y }.average() - upper.map { it.y }.average() >
                            max(1f, box.height() * .008f)
                )
                    upper + lower
                else emptyList()
            val mouthRegion = region(mouth, width, height)
            val radius =
                (box.width().toFloat() / width * sourceWidth * .035f).roundToInt().coerceIn(3, 12)
            val blue = (radius * 255f / 12f).roundToInt()
            val feather = max(1f, box.width() * .025f)
            for (y in max(0, box.top) until min(height, box.bottom)) {
                for (x in max(0, box.left) until min(width, box.right)) {
                    val fx = (x - box.left).toFloat() / box.width()
                    val fy = (y - box.top).toFloat() / box.height()
                    val ellipse = ((fx - .5f) / .47f).pow(2) + ((fy - .52f) / .49f).pow(2)
                    val eyeZone = fy > .22f && fy < .48f
                    val noseZone = abs(fx - .5f) < .11f && fy > .36f && fy < .7f
                    val lipsZone = fy > .66f && fy < .9f && abs(fx - .5f) < .32f
                    val excluded =
                        eyeZone ||
                            noseZone ||
                            lipsZone ||
                            eyes.any { (p, r, b) ->
                                b.contains(x, y) &&
                                    (r.contains(x, y) || distance(x + .5f, y + .5f, p) < feather)
                            }
                    val red =
                        if (
                            ellipse < 1 &&
                                !excluded &&
                                (outline.isEmpty() || outlineRegion.contains(x, y))
                        )
                            (255 * ramp(1f - ellipse, 0f, .18f)).roundToInt()
                        else 0
                    val green =
                        if (mouthRegion.contains(x, y))
                            (255 *
                                    ramp(
                                        distance(x + .5f, y + .5f, mouth),
                                        0f,
                                        max(1f, box.width() * .012f),
                                    ))
                                .roundToInt()
                        else 0
                    val old = pixels[y * width + x]
                    pixels[y * width + x] =
                        Color.rgb(
                            max(Color.red(old), red),
                            max(Color.green(old), green),
                            max(Color.blue(old), blue),
                        )
                }
            }
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }
}
