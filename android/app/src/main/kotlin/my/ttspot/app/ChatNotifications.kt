package my.ttspot.app

import android.app.ActivityManager
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Shader
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.content.ContextCompat
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.firebase.messaging.ContextHolder
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingStore
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Chat pushes drawn as Android conversations: MessagingStyle with the sender
 * as a Person whose icon is their round avatar, one notification per chat
 * (new messages stack into it), the app's monochrome status-bar icon, and a
 * long-lived conversation shortcut so Android 11+ files it under
 * Conversations.
 *
 * Data keys (all strings, from supabase/functions/push): kind=chat, route,
 * conversation_id, title (the chat's name for me: my nickname for them, else
 * their name, or the club / partner / meet), body, sender_id, sender_name,
 * avatar (URL), group ("1" for meet chats), convo_title.
 *
 * Tapping opens the chat exactly like an FCM notification: the message is
 * kept in firebase_messaging's own store and the intent carries its
 * google.message_id, so Dart gets it from getInitialMessage() /
 * onMessageOpenedApp and pushes data.route (lib/core/push/push_service.dart).
 */
object ChatNotifications {
    private const val TAG = "ChatNotifications"
    const val CHANNEL = "chat_messages"
    private const val NOTIFY_TAG = "chat"
    private const val MAX_STACKED = 7
    private const val AVATAR_PX = 192

    /** Same test the plugin uses to route a message to onMessage: a visible activity, screen unlocked. */
    fun appInForeground(context: Context): Boolean {
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguard?.isKeyguardLocked == true) return false
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
        val processes = am.runningAppProcesses ?: return false
        return processes.any {
            it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND && it.processName == context.packageName
        }
    }

    /** Dart calls cancel(conversationId) when that chat opens, so read messages leave the shade. */
    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, "my.ttspot.app/chat_notifications").setMethodCallHandler { call, result ->
            when (call.method) {
                "cancel" -> {
                    val id = call.argument<String>("conversationId")
                    if (id != null) NotificationManagerCompat.from(context).cancel(NOTIFY_TAG, id.hashCode())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun show(context: Context, message: RemoteMessage) {
        try {
            build(context, message)
        } catch (e: Exception) {
            Log.w(TAG, "chat notification failed", e)
        }
    }

    private fun build(context: Context, message: RemoteMessage) {
        val d = message.data
        val conversationId = d["conversation_id"]?.takeIf { it.isNotEmpty() } ?: return
        val title = d["title"]?.takeIf { it.isNotBlank() } ?: "TT Spot"
        val body = d["body"] ?: ""
        val group = d["group"] == "1"
        val senderName = d["sender_name"]?.takeIf { it.isNotBlank() } ?: title
        val senderKey = d["sender_id"]?.takeIf { it.isNotEmpty() } ?: conversationId
        val conversationTitle = d["convo_title"]?.takeIf { it.isNotBlank() } ?: title

        ensureChannel(context)
        val avatar = downloadAvatar(d["avatar"]) ?: appIconBitmap(context)
        val icon = avatar?.let { IconCompat.createWithBitmap(it) } ?: IconCompat.createWithResource(context, R.mipmap.ic_launcher)
        val sender = Person.Builder().setName(if (group) senderName else title).setKey(senderKey).setIcon(icon).build()
        val me = Person.Builder().setName("You").setKey("me").build()

        val id = conversationId.hashCode()
        val style = NotificationCompat.MessagingStyle(me)
        // Earlier unread messages of this chat stay in the same notification.
        previousStyle(context, id)?.messages?.takeLast(MAX_STACKED - 1)?.forEach { style.addMessage(it) }
        val sentAt = if (message.sentTime > 0) message.sentTime else System.currentTimeMillis()
        style.addMessage(NotificationCompat.MessagingStyle.Message(body, sentAt, sender))
        if (group) {
            style.conversationTitle = conversationTitle
            style.isGroupConversation = true
        }

        val tap = tapIntent(context, message)
        val pending = PendingIntent.getActivity(context, id, tap, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val shortcutId = "chat_$conversationId"
        val hasShortcut = pushShortcut(context, shortcutId, if (group) conversationTitle else title, icon, sender, conversationId)

        val builder = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setColor(ContextCompat.getColor(context, R.color.notification_red))
            .setStyle(style)
            .setContentTitle(if (group) conversationTitle else title)
            .setContentText(if (group) "$senderName: $body" else body)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setWhen(sentAt)
            .setShowWhen(true)
            .setAutoCancel(true)
            .setContentIntent(pending)
        // Before Android 9 MessagingStyle has no avatars: show it as the large icon.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P && avatar != null) builder.setLargeIcon(avatar)
        if (hasShortcut) builder.setShortcutId(shortcutId)
        NotificationManagerCompat.from(context).notify(NOTIFY_TAG, id, builder.build())
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Messages", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Chats with friends, clubs, partners and meet groups"
            },
        )
    }

    /** The MessagingStyle of this chat's notification if it's still in the shade. */
    private fun previousStyle(context: Context, id: Int): NotificationCompat.MessagingStyle? {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return null
        val active = try { nm.activeNotifications } catch (e: Exception) { return null }
        val existing = active.firstOrNull { it.id == id && it.tag == NOTIFY_TAG }?.notification ?: return null
        return NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(existing)
    }

    /**
     * The launcher intent, carrying the message the way an FCM notification
     * tap does: google.message_id (looked up in the plugin's store) plus the
     * data keys.
     */
    private fun tapIntent(context: Context, message: RemoteMessage): Intent {
        if (ContextHolder.getApplicationContext() == null) ContextHolder.setApplicationContext(context.applicationContext)
        val stored = if (message.messageId != null) message else RemoteMessage.Builder("${context.packageName}@fcm.googleapis.com")
            .setMessageId("ttspot-${System.currentTimeMillis()}")
            .setData(message.data)
            .build()
        FlutterFirebaseMessagingStore.getInstance().storeFirebaseMessage(stored)
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        intent.putExtra("google.message_id", stored.messageId)
        for ((k, v) in message.data) intent.putExtra(k, v)
        return intent
    }

    /**
     * A long-lived sharing shortcut for the chat, which Android 11+ needs to
     * treat the notification as a conversation. Opens ttspot://chat/<id>.
     */
    private fun pushShortcut(context: Context, shortcutId: String, label: String, icon: IconCompat, person: Person, conversationId: String): Boolean = try {
        val open = Intent(Intent.ACTION_VIEW, Uri.parse("ttspot://chat/$conversationId")).setPackage(context.packageName)
        val info = ShortcutInfoCompat.Builder(context, shortcutId)
            .setLongLived(true)
            .setShortLabel(label.take(25).ifBlank { "Chat" })
            .setLongLabel(label.ifBlank { "Chat" })
            .setIcon(icon)
            .setIntent(open)
            .setPerson(person)
            .build()
        ShortcutManagerCompat.pushDynamicShortcut(context, info)
        true
    } catch (e: Exception) {
        Log.w(TAG, "shortcut failed", e)
        false
    }

    /** The sender's photo, cropped round; null after ~6 s or on any error. */
    private fun downloadAvatar(url: String?): Bitmap? {
        if (url.isNullOrBlank() || !url.startsWith("https://")) return null
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 3000
                readTimeout = 3000
                instanceFollowRedirects = true
            }
            if (conn.responseCode !in 200..299) return null
            val bytes = conn.inputStream.use { input ->
                val out = ByteArrayOutputStream()
                val buf = ByteArray(16 * 1024)
                var total = 0
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > 4 * 1024 * 1024) return null
                    out.write(buf, 0, n)
                }
                out.toByteArray()
            }
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= AVATAR_PX && bounds.outHeight / (sample * 2) >= AVATAR_PX) sample *= 2
            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
            round(bmp)
        } catch (e: Exception) {
            Log.w(TAG, "avatar download failed: ${e.message}")
            null
        } finally {
            conn?.disconnect()
        }
    }

    private fun appIconBitmap(context: Context): Bitmap? = try {
        val drawable = ContextCompat.getDrawable(context, R.mipmap.ic_launcher)
        drawable?.let {
            val bmp = Bitmap.createBitmap(AVATAR_PX, AVATAR_PX, Bitmap.Config.ARGB_8888)
            it.setBounds(0, 0, AVATAR_PX, AVATAR_PX)
            it.draw(Canvas(bmp))
            round(bmp)
        }
    } catch (e: Exception) {
        null
    }

    /** Centre square, scaled to AVATAR_PX, inside a circle. */
    private fun round(src: Bitmap): Bitmap {
        val side = minOf(src.width, src.height)
        val out = Bitmap.createBitmap(AVATAR_PX, AVATAR_PX, Bitmap.Config.ARGB_8888)
        val scale = AVATAR_PX.toFloat() / side
        val m = Matrix().apply {
            setTranslate(-(src.width - side) / 2f, -(src.height - side) / 2f)
            postScale(scale, scale)
        }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            shader = BitmapShader(src, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply { setLocalMatrix(m) }
        }
        Canvas(out).drawCircle(AVATAR_PX / 2f, AVATAR_PX / 2f, AVATAR_PX / 2f, paint)
        return out
    }
}
