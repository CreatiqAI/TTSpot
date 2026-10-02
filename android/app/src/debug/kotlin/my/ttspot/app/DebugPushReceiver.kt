package my.ttspot.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseRemoteMessageLiveData

/**
 * DEBUG BUILDS ONLY (src/debug): fakes an FCM data message so the push paths
 * can be checked on an emulator whose FCM registration fails. Same routing
 * as a real delivery: app open → Dart's onMessage (in-app banner); app in
 * the background → ChatNotifications (system notification). Every string
 * extra becomes a data key, e.g.
 *
 *   adb shell am broadcast -n my.ttspot.app/.DebugPushReceiver \
 *     --es kind chat --es conversation_id <id> --es route /chat/<id> \
 *     --es title Aiman --es body "TEST hi" --es sender_id <uuid> --es avatar <https url>
 */
class DebugPushReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val data = HashMap<String, String>()
        intent.extras?.keySet()?.forEach { k -> intent.getStringExtra(k)?.let { data[k] = it } }
        val message = RemoteMessage.Builder("${context.packageName}@fcm.googleapis.com")
            .setMessageId("debug-${System.currentTimeMillis()}")
            .setData(data)
            .build()
        if (ChatNotifications.appInForeground(context)) {
            FlutterFirebaseRemoteMessageLiveData.getInstance().postRemoteMessage(message)
            return
        }
        val pending = goAsync()
        Thread {
            try {
                ChatNotifications.show(context.applicationContext, message)
            } finally {
                pending.finish()
            }
        }.start()
    }
}
