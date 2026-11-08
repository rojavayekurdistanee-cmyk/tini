package com.aras.titistar

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import kotlin.math.max

/** Native attestation for CPU-frame -> hardware AVC encoding. */
object TiniHardwareVideoCodec {
    @JvmStatic
    fun probe(width: Int, height: Int): Map<String, Any>? {
        if (Build.VERSION.SDK_INT < 29 || width < 2 || height < 2 ||
            width % 2 != 0 || height % 2 != 0) return null
        val requestedBitrate = max(4_000_000,
            (width.toLong() * height * 30 / 3).coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
        val codecs = try {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
        } catch (_: Exception) { return null }
        for (info in codecs) {
            try {
                if (!info.isEncoder || !info.isHardwareAccelerated || info.isSoftwareOnly ||
                    info.supportedTypes.none { it.equals(MediaFormat.MIMETYPE_VIDEO_AVC, true) }) continue
                val caps = info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
                val formats = caps.colorFormats
                val semiplanar = formats.contains(MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar)
                if (!semiplanar && !formats.contains(MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar) &&
                    !formats.contains(MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)) continue
                if (!caps.videoCapabilities.areSizeAndRateSupported(width, height, 30.0)) continue
                val vbr = caps.encoderCapabilities.isBitrateModeSupported(
                    MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
                if (!vbr && !caps.encoderCapabilities.isBitrateModeSupported(
                    MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)) continue
                if (caps.videoCapabilities.bitrateRange.upper < requestedBitrate) continue
                return mapOf(
                    "name" to info.name, "hardware" to true,
                    "pixelFormat" to if (semiplanar) "nv12" else "yuv420p",
                    "bitrate" to caps.videoCapabilities.bitrateRange.clamp(requestedBitrate),
                    "vbr" to vbr,
                    "high" to caps.profileLevels.any {
                        it.profile == MediaCodecInfo.CodecProfileLevel.AVCProfileHigh },
                    "operatingRate" to caps.videoCapabilities
                        .getSupportedFrameRatesFor(width, height).upper.toInt().coerceIn(30, 240),
                )
            } catch (_: Exception) {
                // A broken vendor capability must not hide another usable codec.
            }
        }
        return null
    }
}
