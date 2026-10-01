package my.ttspot.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * After a reboot or an app update the location service is gone. Bring it back
 * only when the member left "Share location when TT Spot is closed" on, it isn't
 * paused (Nobody), and "Allow all the time" is still granted.
 */
class BgLocationBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> BgLocationService.start(context)
        }
    }
}
