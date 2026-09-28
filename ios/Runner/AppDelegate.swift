import CoreMotion
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let motion = CMMotionManager()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Accelerometer in g, ~50 Hz, only while Dart listens (blind-box shake, tilt parallax).
    // Mirrors MainActivity.kt; see lib/core/motion/motion.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TTSpotMotion") {
      let channel = FlutterEventChannel(name: "my.ttspot.app/motion", binaryMessenger: registrar.messenger())
      channel.setStreamHandler(MotionStreamHandler(motion: motion))
    }
  }
}

private class MotionStreamHandler: NSObject, FlutterStreamHandler {
  private let motion: CMMotionManager
  init(motion: CMMotionManager) { self.motion = motion }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard motion.isAccelerometerAvailable else {
      return FlutterError(code: "unavailable", message: "No accelerometer", details: nil)
    }
    motion.accelerometerUpdateInterval = 1.0 / 50.0
    motion.startAccelerometerUpdates(to: .main) { data, _ in
      guard let a = data?.acceleration else { return }
      // Match Android's axes: iOS reports +x to the right, +y up, +z out of the screen; Android's
      // accelerometer reports the reaction force, so the sign flips.
      events([-a.x, -a.y, -a.z])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    motion.stopAccelerometerUpdates()
    return nil
  }
}
