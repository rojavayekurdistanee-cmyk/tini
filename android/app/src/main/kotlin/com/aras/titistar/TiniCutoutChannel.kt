package com.aras.titistar

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.Segmentation
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Bundled on-device ML Kit person segmentation. Never blocks Android's UI thread. */
internal class TiniCutoutChannel(engine: FlutterEngine) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val cancelled = AtomicBoolean(false)
    private val busy = AtomicBoolean(false)
    @Volatile private var progressSink: EventChannel.EventSink? = null

    init {
        EventChannel(engine.dartExecutor.binaryMessenger, "titi_star/cutout/progress")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    progressSink = events
                }
                override fun onCancel(arguments: Any?) { progressSink = null }
            })
        MethodChannel(engine.dartExecutor.binaryMessenger, "titi_star/cutout")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "cancel" -> {
                        cancelled.set(true)
                        result.success(null)
                    }
                    "createMasks", "applyStrokes" -> {
                        if (!busy.compareAndSet(false, true)) {
                            result.error("BUSY", "هناك معالجة خلفية جارية", null)
                        } else {
                            cancelled.set(false)
                            worker.execute {
                                try {
                                    val response = if (call.method == "createMasks") {
                                        val path = requireNotNull(call.argument<String>("path"))
                                        val dir = requireNotNull(call.argument<String>("outputDir"))
                                        val start = (call.argument<Number>("startMs") ?: 0).toLong()
                                        val duration = (call.argument<Number>("durationMs") ?: 0).toLong()
                                        val fps = (call.argument<Number>("fps") ?: 10).toInt().coerceIn(4, 15)
                                        val size = (call.argument<Number>("size") ?: 320).toInt().coerceIn(256, 512)
                                        createMasks(path, File(dir), start, duration, fps, size)
                                    } else {
                                        val src = File(requireNotNull(call.argument<String>("inputDir")))
                                        val dst = File(requireNotNull(call.argument<String>("outputDir")))
                                        @Suppress("UNCHECKED_CAST")
                                        val strokes = call.argument<List<Map<String, Any>>>("strokes") ?: emptyList()
                                        applyStrokes(src, dst, strokes)
                                        mapOf("directory" to dst.absolutePath)
                                    }
                                    main.post { result.success(response) }
                                } catch (e: Exception) {
                                    main.post { result.error("CUTOUT_FAILED", e.message ?: "Cutout failed", null) }
                                } finally { busy.set(false) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun createMasks(path: String, dir: File, startMs: Long,
                            durationMs: Long, fps: Int, size: Int): Map<String, Any> {
        require(durationMs > 0) { "Invalid segment duration" }
        if (!dir.mkdirs()) require(dir.isDirectory) { "Cannot create output directory" }
        val retriever = MediaMetadataRetriever()
        val segmenter = Segmentation.getClient(
            SelfieSegmenterOptions.Builder()
                .setDetectorMode(SelfieSegmenterOptions.STREAM_MODE)
                .enableRawSizeMask()
                .build()
        )
        var count = 0
        try {
            retriever.setDataSource(path)
            val totalMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0L
            require(startMs >= 0 && startMs + durationMs <= totalMs + 75L) { "Segment outside video" }
            val frames = max(1, (durationMs * fps / 1000.0).roundToInt())
            for (index in 0 until frames) {
                if (cancelled.get()) throw InterruptedException("تم إلغاء عملية قص الخلفية")
                val atUs = (startMs * 1000 + (index.toDouble() * 1_000_000 / fps).toLong())
                val frame = retriever.getFrameAtTime(atUs, MediaMetadataRetriever.OPTION_CLOSEST)
                    ?: throw IllegalStateException("Cannot decode video at frame $index")
                val targetW = if (frame.width >= frame.height) size else max(1, size * frame.width / frame.height)
                val targetH = if (frame.height > frame.width) size else max(1, size * frame.height / frame.width)
                val scaled = Bitmap.createScaledBitmap(frame, targetW, targetH, true)
                if (scaled !== frame) frame.recycle()
                try {
                    val segmentation = Tasks.await(segmenter.process(InputImage.fromBitmap(scaled, 0)))
                    val src = segmentation.buffer.duplicate().order(ByteOrder.nativeOrder())
                    val mw = segmentation.width
                    val mh = segmentation.height
                    val pixels = IntArray(mw * mh)
                    for (i in pixels.indices) {
                        val confidence = src.getFloat().coerceIn(0f, 1f)
                        val shade = (confidence * 255f).roundToInt()
                        pixels[i] = Color.rgb(shade, shade, shade)
                    }
                    val raw = Bitmap.createBitmap(mw, mh, Bitmap.Config.ARGB_8888)
                    raw.setPixels(pixels, 0, mw, 0, 0, mw, mh)
                    val mask = Bitmap.createScaledBitmap(raw, targetW, targetH, true)
                    // Force ASCII digits: Arabic device locales format %d with Arabic-Indic digits,
                    // while FFmpeg image2 expects filenames such as mask_000000.png.
                    FileOutputStream(File(dir, String.format(Locale.US, "mask_%06d.png", index))).use {
                        mask.compress(Bitmap.CompressFormat.PNG, 100, it)
                    }
                    if (raw !== mask) raw.recycle()
                    mask.recycle()
                    count++
                    val completion = ((count * 100.0) / frames).roundToInt().coerceIn(0, 100)
                    main.post { progressSink?.success(completion) }
                } finally { scaled.recycle() }
            }
            return mapOf("count" to count, "fps" to fps, "directory" to dir.absolutePath)
        } catch (error: Exception) {
            dir.deleteRecursively()
            throw error
        } finally {
            try { segmenter.close() } catch (_: Exception) {}
            try { retriever.release() } catch (_: Exception) {}
        }
    }

    private fun applyStrokes(source: File, output: File, strokes: List<Map<String, Any>>) {
        require(source.isDirectory) { "Mask source is missing" }
        require(output.mkdirs()) { "Cannot create edited mask directory" }
        val files = source.listFiles { file -> file.name.startsWith("mask_") && file.extension == "png" }
            ?.sortedBy { it.name } ?: emptyList()
        try {
            for (file in files) {
                if (cancelled.get()) throw InterruptedException("تم إلغاء العملية")
                val decoded = android.graphics.BitmapFactory.decodeFile(file.absolutePath)
                    ?: throw IllegalStateException("Cannot decode mask")
                // BitmapFactory may return an immutable bitmap. Canvas requires
                // a mutable copy or manual brush strokes throw at runtime.
                val bitmap = decoded.copy(Bitmap.Config.ARGB_8888, true)
                decoded.recycle()
                val canvas = Canvas(bitmap)
                for (stroke in strokes) {
                    @Suppress("UNCHECKED_CAST")
                    val points = stroke["points"] as? List<List<Number>> ?: continue
                    if (points.isEmpty()) continue
                    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = if (stroke["erase"] == true) Color.BLACK else Color.WHITE
                        style = Paint.Style.STROKE
                        strokeCap = Paint.Cap.ROUND
                        strokeJoin = Paint.Join.ROUND
                        strokeWidth = ((stroke["radius"] as? Number)?.toFloat() ?: .02f) *
                            min(bitmap.width, bitmap.height) * 2f
                    }
                    if (points.size == 1) {
                        val x = points[0][0].toFloat() * bitmap.width
                        val y = points[0][1].toFloat() * bitmap.height
                        canvas.drawCircle(x, y, paint.strokeWidth / 2f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            color = paint.color
                        })
                    } else {
                        val path = Path()
                        path.moveTo(points[0][0].toFloat() * bitmap.width,
                                    points[0][1].toFloat() * bitmap.height)
                        for (point in points.drop(1)) {
                            path.lineTo(point[0].toFloat() * bitmap.width,
                                        point[1].toFloat() * bitmap.height)
                        }
                        canvas.drawPath(path, paint)
                    }
                }
                FileOutputStream(File(output, file.name)).use {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
                bitmap.recycle()
            }
        } catch (e: Exception) {
            output.deleteRecursively()
            throw e
        }
    }
}
