package com.aras.titistar

import android.app.Notification
import android.app.NotificationManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.Paint
import android.graphics.Shader
import android.service.notification.StatusBarNotification
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService
import java.net.HttpURLConnection
import java.net.URL

/** Adds media to an already posted FCM notification; never replaces delivery. */
class TiniNotificationService : FlutterFirebaseMessagingService() {
    override fun handleIntent(intent: Intent) {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager == null) {
            super.handleIntent(intent)
            return
        }
        val before = try {
            manager.activeNotifications.associate { it.key to it.postTime }
        } catch (_: Exception) {
            emptyMap<String, Long>()
        }

        // Always let Firebase handle delivery, deduplication, foreground detection,
        // analytics and its original contentIntent before attempting any decoration.
        super.handleIntent(intent)

        try {
            if (intent.action != "com.google.android.c2dm.intent.RECEIVE") return
            if (intent.getStringExtra("gcm.n.e") != "1") return
            if (intent.getStringExtra("type") !in SOCIAL_TYPES) return
            val title = intent.getStringExtra("gcm.n.title") ?: return
            val body = intent.getStringExtra("gcm.n.body") ?: return
            // NotificationManager enqueues posts asynchronously. Allow a short
            // bounded interval for Firebase's alert to become visible to queries.
            var posted: StatusBarNotification? = null
            for (attempt in 0 until 6) {
                posted = manager.activeNotifications.singleOrNull {
                    before[it.key] != it.postTime &&
                        it.notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() == title &&
                        it.notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() == body
                }
                if (posted != null) break
                if (attempt < 5) android.os.SystemClock.sleep(50)
            }
            if (posted == null) return
            decorate(manager, posted, intent, title, body)
        } catch (_: Exception) {
            // Permissions, image errors or OEM behavior must leave FCM's alert intact.
        }
    }

    private fun decorate(
        manager: NotificationManager,
        posted: StatusBarNotification,
        intent: Intent,
        title: String,
        body: String
    ) {
        val avatarUrl = intent.getStringExtra("avatar")
        val avatar = if (avatarUrl.isNullOrBlank()) letterAvatar(title)
            else download(avatarUrl)?.let(::circleAvatar)
        val postImage = intent.getStringExtra("postImage")
        val thumbnail = download(postImage)
        if (avatar == null && thumbnail == null) return

        // Recover the actual Firebase notification, including its PendingIntent,
        // channel, small icon, sound, extras and analytics/delete intents.
        val builder = Notification.Builder.recoverBuilder(this, posted.notification)
            .setOnlyAlertOnce(true)
        if (avatar != null) builder.setLargeIcon(avatar)
        if (thumbnail != null) {
            builder.setStyle(
                Notification.BigPictureStyle()
                    .bigPicture(thumbnail)
                    .bigLargeIcon(null as Bitmap?)
                    .setBigContentTitle(title)
                    .setSummaryText(body)
            )
        } else if (postImage.isNullOrBlank() && avatar != null) {
            // Match Flutter's existing profile-only layout for follow events.
            builder.setStyle(
                Notification.BigPictureStyle()
                    .bigPicture(avatar)
                    .bigLargeIcon(avatar)
                    .setBigContentTitle(title)
                    .setSummaryText(body)
            )
        }

        // Never resurrect an alert that was tapped/dismissed while images loaded,
        // or overwrite a newer notification using an explicitly reused FCM tag.
        val current = manager.activeNotifications.singleOrNull { it.key == posted.key }
            ?: return
        if (current.postTime != posted.postTime) return
        manager.notify(posted.tag, posted.id, builder.build())
    }

    private fun download(value: String?): Bitmap? {
        if (value.isNullOrBlank()) return null
        return try {
            val url = URL(value)
            if (url.protocol != "https") return null
            val connection = url.openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 2000
                connection.readTimeout = 2000
                if (connection.responseCode != HttpURLConnection.HTTP_OK) return null
                val bytes = connection.inputStream.use { stream ->
                    // Bound both download size and decoded bitmap memory.
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    val deadline = android.os.SystemClock.elapsedRealtime() + 2500
                    while (true) {
                        if (android.os.SystemClock.elapsedRealtime() > deadline) return null
                        val count = stream.read(buffer)
                        if (count < 0) break
                        if (output.size() + count > MAX_IMAGE_BYTES) return null
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                if (options.outWidth <= 0 || options.outHeight <= 0) return null
                options.inSampleSize = 1
                while (maxOf(options.outWidth, options.outHeight) / options.inSampleSize > 1024) {
                    options.inSampleSize *= 2
                }
                options.inJustDecodeBounds = false
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
            } finally {
                connection.disconnect()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun letterAvatar(title: String): Bitmap {
        val result = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(result)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(0, 150, 136) }
        canvas.drawCircle(128f, 128f, 128f, paint)
        paint.color = Color.WHITE
        paint.textSize = 120f
        paint.typeface = Typeface.DEFAULT_BOLD
        paint.textAlign = Paint.Align.CENTER
        val letter = title.trim().take(1).uppercase().ifEmpty { "?" }
        canvas.drawText(letter, 128f, 128f - (paint.ascent() + paint.descent()) / 2, paint)
        return result
    }

    private fun circleAvatar(source: Bitmap): Bitmap {
        val side = minOf(source.width, source.height)
        val crop = Bitmap.createBitmap(source, (source.width - side) / 2,
            (source.height - side) / 2, side, side)
        val scaled = Bitmap.createScaledBitmap(crop, 256, 256, true)
        val result = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(result)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = BitmapShader(scaled, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }
        canvas.drawCircle(128f, 128f, 128f, paint)
        // Match the badge used by Flutter's _createAvatarWithBadge.
        try {
            val badge = assets.open("flutter_assets/assets/icon.png").use {
                BitmapFactory.decodeStream(it)
            }
            if (badge != null) {
                val small = Bitmap.createScaledBitmap(badge, 80, 80, true)
                paint.shader = BitmapShader(small, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
                canvas.save()
                canvas.translate(171f, 171f)
                canvas.drawCircle(40f, 40f, 40f, paint)
                canvas.restore()
            }
        } catch (_: Exception) { /* The avatar remains usable without its badge. */ }
        return result
    }

    private companion object {
        const val MAX_IMAGE_BYTES = 4 * 1024 * 1024
        val SOCIAL_TYPES = setOf("like", "comment", "follow", "new_follower", "new_followers")
    }
}
