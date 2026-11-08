
package com.aras.titistar

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterFragmentActivity() {
    private var retouchPreview: TiniRetouchPreviewChannel? = null
    private var retouchExport: TiniRetouchExportChannel? = null
    private var media3Export: TiniMedia3ExportChannel? = null
    private val CHANNEL = "titi_star/thumbnails"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        retouchPreview?.dispose()
        retouchPreview = TiniRetouchPreviewChannel(flutterEngine, this)
        retouchExport?.dispose()
        retouchExport = TiniRetouchExportChannel(flutterEngine)
        media3Export?.dispose()
        media3Export = TiniMedia3ExportChannel(flutterEngine, this)
        // Background and Cutout use their own channel and native worker queue.
        // The existing thumbnail and privacy channel remains unchanged.
        TiniCutoutChannel(flutterEngine)
        // Separate pose + mask channel for editor body effects.
        TiniBodyTrackingChannel(flutterEngine)
        // Isolated ML Kit face sampling for the single Bobsledder effect.
        TiniSledFaceChannel(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call,
            result ->
            if (call.method == "getFrames") {
                val path = call.argument<String>("path")
                val count = call.argument<Int>("count") ?: 4
                val thumbHeight = call.argument<Int>("thumbHeight") ?: 100

                Thread {
                        val frames = getVideoFrames(path!!, count, thumbHeight)
                        runOnUiThread { result.success(frames) }
                    }
                    .start()
            } else if (call.method == "setSecure") {
                // منع لقطة الشاشة/تسجيل الشاشة أثناء عرض رسائل "مرة واحدة"
                val secure = call.argument<Boolean>("secure") ?: false
                runOnUiThread {
                    if (secure) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onPause() {
        retouchPreview?.pauseAll()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        retouchPreview?.resumeAll()
    }

    override fun onDestroy() {
        retouchPreview?.dispose()
        retouchPreview = null
        retouchExport?.dispose()
        retouchExport = null
        media3Export?.dispose()
        media3Export = null
        super.onDestroy()
    }

    private fun getVideoFrames(path: String, count: Int, thumbHeight: Int): List<ByteArray> {
        val retriever = MediaMetadataRetriever()
        val frames = mutableListOf<ByteArray>()

        try {
            retriever.setDataSource(path)
            val durationStr =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val duration = durationStr?.toLong() ?: 0
            val interval = duration / (count + 1)

            for (i in 1..count) {
                val timeUs = i * interval * 1000
                val bitmap =
                    retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)

                bitmap?.let {
                    // --- بداية التعديل عشان يصير مربع متل تيكتوك ---
                    // 1. قص مربع من نص الفيديو
                    val dimension = minOf(it.width, it.height)
                    val x = (it.width - dimension) / 2
                    val y = (it.height - dimension) / 2
                    val cropped = Bitmap.createBitmap(it, x, y, dimension, dimension)

                    // 2. صغر المربع لـ thumbHeight x thumbHeight
                    val scaled = Bitmap.createScaledBitmap(cropped, thumbHeight, thumbHeight, true)
                    // --- نهاية التعديل ---

                    val stream = ByteArrayOutputStream()
                    scaled.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                    frames.add(stream.toByteArray())

                    cropped.recycle()
                    scaled.recycle()
                    it.recycle()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            retriever.release()
        }
        return frames
    }
}
