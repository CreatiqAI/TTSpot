package my.ttspot.app

import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Takes the place of firebase_messaging's own service (AndroidManifest.xml
 * removes that one). Token refreshes still go to the plugin through super.
 *
 * Chat messages arrive as data-only pushes (the `push` Edge Function sends
 * them that way to Android), so FCM draws nothing for them: with the app in
 * the background or closed, ChatNotifications draws a conversation-style
 * notification with the sender's avatar; with the app open, nothing is
 * posted and Dart shows its in-app banner (FirebaseMessaging.onMessage).
 * Everything else (likes, friend requests, meets) keeps the standard FCM
 * notification payload, which the system draws only in the background.
 */
class ChatPushService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        if (remoteMessage.notification != null) return
        if (remoteMessage.data["kind"] != "chat") return
        if (ChatNotifications.appInForeground(this)) return
        ChatNotifications.show(applicationContext, remoteMessage)
    }
}
