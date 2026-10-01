package my.ttspot.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val bgPermissionRequest = 4108
    private var pendingBgPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "Share location when TT Spot is closed": the foreground service in
        // BgLocationService.kt. Dart side: lib/core/location/background_location.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "my.ttspot.app/bglocation").setMethodCallHandler { call, result ->
            val ctx = applicationContext
            when (call.method) {
                "status" -> result.success(BgLocationStore.status(ctx))
                "start" -> {
                    val url = call.argument<String>("url")
                    val key = call.argument<String>("key")
                    val token = call.argument<String>("token")
                    val userId = call.argument<String>("userId")
                    if (url.isNullOrEmpty() || key.isNullOrEmpty() || token.isNullOrEmpty() || userId.isNullOrEmpty()) {
                        result.error("bad_args", "url, key, token and userId are required", null)
                    } else {
                        BgLocationStore.save(ctx, url, key, token, userId, call.argument<String>("devCa"))
                        result.success(BgLocationService.start(ctx))
                    }
                }
                // Nobody (ghost): stop the service but keep the token.
                "pause" -> {
                    BgLocationStore.setPaused(ctx, true)
                    BgLocationService.stop(ctx)
                    result.success(null)
                }
                "resume" -> {
                    BgLocationStore.setPaused(ctx, false)
                    result.success(BgLocationService.start(ctx))
                }
                "stop" -> {
                    BgLocationService.forget(ctx, "off", revoke = call.argument<Boolean>("revoke") ?: true)
                    result.success(null)
                }
                "requestBackground" -> requestBackgroundPermission(result)
                else -> result.notImplemented()
            }
        }

        // Settings → Push notifications → "Open phone settings". url_launcher can only
        // send VIEW intents, so the app's notification screen is opened from here.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "my.ttspot.app/settings").setMethodCallHandler { call, result ->
            if (call.method != "openNotificationSettings") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
            }
            try {
                startActivity(intent)
                result.success(true)
            } catch (e: Exception) {
                result.success(false)
            }
        }
        // Garage cut-outs (ML Kit subject segmentation); see CarCutout.kt.
        CarCutout.register(flutterEngine.dartExecutor.binaryMessenger, this)

        // Accelerometer in g (gravity included), ~50 Hz, only while Dart listens.
        // Used by the blind-box shake-to-open and the tilt parallax; see lib/core/motion/motion.dart.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "my.ttspot.app/motion").setStreamHandler(object : EventChannel.StreamHandler {
            private var listener: SensorEventListener? = null
            private val manager get() = getSystemService(Context.SENSOR_SERVICE) as SensorManager

            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val sensor = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                if (sensor == null) {
                    events.error("unavailable", "No accelerometer", null)
                    return
                }
                val l = object : SensorEventListener {
                    override fun onSensorChanged(e: SensorEvent) {
                        val g = SensorManager.GRAVITY_EARTH
                        events.success(listOf((e.values[0] / g).toDouble(), (e.values[1] / g).toDouble(), (e.values[2] / g).toDouble()))
                    }
                    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                }
                listener = l
                manager.registerListener(l, sensor, SensorManager.SENSOR_DELAY_GAME)
            }

            override fun onCancel(arguments: Any?) {
                listener?.let { manager.unregisterListener(it) }
                listener = null
            }
        })
    }

    /**
     * "Allow all the time". Android 10 shows it in the dialog; Android 11+ can't
     * ask inline, so the system opens TT Spot's location page in Settings and the
     * answer comes back when the member returns. Replies true when granted.
     */
    private fun requestBackgroundPermission(result: MethodChannel.Result) {
        if (BgLocationStore.hasBackgroundPermission(this)) {
            result.success(true)
            return
        }
        if (!BgLocationStore.hasForegroundPermission(this) || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(false)
            return
        }
        pendingBgPermission?.success(false)
        pendingBgPermission = result
        requestPermissions(arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), bgPermissionRequest)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        if (requestCode == bgPermissionRequest) {
            pendingBgPermission?.success(BgLocationStore.hasBackgroundPermission(this))
            pendingBgPermission = null
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
