package my.ttspot.app

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
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}
