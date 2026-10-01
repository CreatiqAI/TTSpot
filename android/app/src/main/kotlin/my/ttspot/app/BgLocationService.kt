package my.ttspot.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import org.json.JSONObject
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Foreground service behind "Share location when TT Spot is closed".
 *
 * Runs with a low-importance ongoing notification (with a Stop button) and keeps
 * going after the app is swiped away (no stopWithTask). Balanced-power fixes
 * about every 30 s / 50 m from Google Play services, or the platform
 * LocationManager on phones without them (Huawei). Each fix is posted to
 * push_location_by_token with the per-phone token; the server throttles, obeys
 * the member's map visibility and answers "invalid" once the token is revoked,
 * which stops this service for good.
 */
class BgLocationService : Service() {
    companion object {
        private const val TAG = "TTSpotBgLocation"
        const val ACTION_START = "my.ttspot.app.bglocation.START"
        const val ACTION_STOP = "my.ttspot.app.bglocation.STOP"
        private const val CHANNEL = "ttspot_location_sharing"
        private const val NOTIFICATION_ID = 4107
        private const val INTERVAL_MS = 30_000L
        private const val MIN_DISTANCE_M = 50f
        private const val THROTTLE_MS = 20_000L

        @Volatile var running = false
            private set

        /** Start (or keep) sharing. Only when it's on, not paused, and "Allow all the time" is granted. */
        fun start(ctx: Context): Boolean {
            if (BgLocationStore.load(ctx) == null || BgLocationStore.isPaused(ctx)) return false
            if (!BgLocationStore.hasBackgroundPermission(ctx)) return false
            val i = Intent(ctx, BgLocationService::class.java).setAction(ACTION_START)
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i) else ctx.startService(i)
                true
            } catch (e: Exception) {
                Log.w(TAG, "start failed: $e")
                false
            }
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, BgLocationService::class.java))
        }

        /** Forget the token here and switch it off on the server (knowing the token is enough). */
        fun forget(ctx: Context, reason: String, revoke: Boolean) {
            val cfg = BgLocationStore.load(ctx)
            BgLocationStore.clear(ctx, reason)
            stop(ctx)
            if (revoke && cfg != null) {
                val app = ctx.applicationContext
                Thread {
                    try {
                        BgLocationStore.rpc(app, cfg, "revoke_location_token", JSONObject().put("p_token", cfg.token))
                    } catch (e: Exception) {
                        Log.w(TAG, "revoke failed: $e")
                    }
                }.start()
            }
        }
    }

    private lateinit var io: ExecutorService
    private val main = Handler(Looper.getMainLooper())
    private var fused: FusedLocationProviderClient? = null
    private var fusedCallback: LocationCallback? = null
    private var platform: LocationManager? = null
    private var platformListener: LocationListener? = null
    private var lastSent: Location? = null
    private var lastSentAt = 0L
    private var showingHidden = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        io = Executors.newSingleThreadExecutor()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // The notification's Stop button.
            stopUpdates()
            forget(this, "stopped", revoke = true)
            stopSelfSafely()
            return START_NOT_STICKY
        }
        // Started by the app, by the boot receiver, or restarted by the system (null intent).
        // startForeground first, always: a startForegroundService() that never reaches it crashes the app.
        try {
            val n = notification(hidden = false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
        } catch (e: Exception) {
            Log.w(TAG, "startForeground refused: $e")
            stopSelfSafely()
            return START_NOT_STICKY
        }
        if (BgLocationStore.load(this) == null || BgLocationStore.isPaused(this) || !BgLocationStore.hasBackgroundPermission(this)) {
            stopSelfSafely()
            return START_NOT_STICKY
        }
        running = true
        startUpdates()
        return START_STICKY
    }

    override fun onDestroy() {
        stopUpdates()
        running = false
        io.shutdown()
        super.onDestroy()
    }

    // ------------------------------------------------------------- location

    private fun startUpdates() {
        if (fusedCallback != null || platformListener != null) return
        try {
            val client = LocationServices.getFusedLocationProviderClient(this)
            val request = LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, INTERVAL_MS)
                .setMinUpdateIntervalMillis(THROTTLE_MS)
                .setMinUpdateDistanceMeters(MIN_DISTANCE_M)
                .build()
            val cb = object : LocationCallback() {
                override fun onLocationResult(result: LocationResult) {
                    result.lastLocation?.let { onLocation(it) }
                }
            }
            fused = client
            fusedCallback = cb
            client.requestLocationUpdates(request, cb, Looper.getMainLooper())
                .addOnFailureListener { e ->
                    // No Google Play services (Huawei and friends): the platform's own provider.
                    Log.w(TAG, "fused unavailable, using LocationManager: $e")
                    client.removeLocationUpdates(cb)
                    fused = null
                    fusedCallback = null
                    startPlatformUpdates()
                }
        } catch (e: SecurityException) {
            stopSelfSafely()
        } catch (e: Exception) {
            startPlatformUpdates()
        }
    }

    private fun startPlatformUpdates() {
        if (platformListener != null) return
        val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return
        val provider = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && lm.hasProvider(LocationManager.FUSED_PROVIDER) -> LocationManager.FUSED_PROVIDER
            lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> LocationManager.GPS_PROVIDER
        }
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) = onLocation(location)
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        try {
            lm.requestLocationUpdates(provider, INTERVAL_MS, MIN_DISTANCE_M, listener, Looper.getMainLooper())
            platform = lm
            platformListener = listener
        } catch (e: Exception) {
            Log.w(TAG, "LocationManager failed: $e")
            stopSelfSafely()
        }
    }

    private fun stopUpdates() {
        fusedCallback?.let { cb -> fused?.removeLocationUpdates(cb) }
        fusedCallback = null
        fused = null
        platformListener?.let { l -> platform?.removeUpdates(l) }
        platformListener = null
        platform = null
    }

    private fun onLocation(loc: Location) {
        if (loc.hasAccuracy() && loc.accuracy > 1000f) return
        val now = System.currentTimeMillis()
        val prev = lastSent
        // Same rule as the server: nothing new within 20 s and 50 m.
        if (prev != null && now - lastSentAt < THROTTLE_MS && prev.distanceTo(loc) < MIN_DISTANCE_M) return
        lastSent = loc
        lastSentAt = now
        if (io.isShutdown) return
        io.execute { push(loc) }
    }

    /** Runs on [io]. */
    private fun push(loc: Location) {
        val cfg = BgLocationStore.load(this)
        if (cfg == null) {
            main.post { stopSelfSafely() }
            return
        }
        val body = JSONObject()
            .put("p_token", cfg.token)
            .put("p_lat", loc.latitude)
            .put("p_lng", loc.longitude)
        if (loc.hasBearing()) body.put("p_heading", loc.bearing.toDouble())
        if (loc.hasAccuracy()) body.put("p_accuracy", loc.accuracy.toDouble())
        if (loc.hasSpeed()) body.put("p_speed", loc.speed.toDouble())
        val status = try {
            val (code, text) = BgLocationStore.rpc(this, cfg, "push_location_by_token", body)
            if (code in 200..299) JSONObject(text ?: "{}").optString("status", "error") else "http_$code"
        } catch (e: Exception) {
            "error: ${e.javaClass.simpleName}"
        }
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            Log.d(TAG, "push ${"%.5f".format(loc.latitude)},${"%.5f".format(loc.longitude)} ±${loc.accuracy.toInt()} m -> $status")
        } else {
            Log.d(TAG, "push -> $status")
        }
        BgLocationStore.setLast(this, status)
        when (status) {
            // Revoked, idle too long, account gone or suspended: stop and forget.
            "invalid" -> main.post {
                stopUpdates()
                forget(this, "invalid", revoke = false)
                stopSelfSafely()
            }
            "hidden" -> main.post { setHidden(true) }
            "ok", "throttled" -> main.post { setHidden(false) }
        }
    }

    // --------------------------------------------------------- notification

    private fun setHidden(hidden: Boolean) {
        if (hidden == showingHidden || !running) return
        showingHidden = hidden
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, notification(hidden))
    }

    private fun notification(hidden: Boolean): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Location sharing", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shows while TT Spot shares your location with the app closed."
                    setShowBadge(false)
                }
            )
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, BgLocationService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        b.setSmallIcon(R.drawable.ic_stat_notify)
            .setColor(getColor(R.color.notification_red))
            .setContentTitle("TT Spot is sharing your location")
            .setContentText(if (hidden) "Paused while your map visibility is Nobody." else "People your map visibility allows can see you. Tap Stop to turn it off.")
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(Notification.Action.Builder(Icon.createWithResource(this, R.drawable.ic_stat_notify), "Stop", stop).build())
        if (open != null) b.setContentIntent(open)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        @Suppress("DEPRECATION")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) b.setPriority(Notification.PRIORITY_LOW)
        return b.build()
    }

    private fun stopSelfSafely() {
        running = false
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {}
        stopSelf()
    }
}
