import CoreImage
import CoreLocation
import CoreMotion
import Flutter
import Security
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let motion = CMMotionManager()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // "Share location when TT Spot is closed". Also runs when iOS relaunches
    // TT Spot in the background for a significant location change
    // (launchOptions[.location]); the manager must exist before this returns.
    BackgroundLocation.shared.resumeIfEnabled()
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
    // Garage cut-outs (Vision, iOS 17+); Dart side: lib/features/profile/data/car_cutout_channel.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TTSpotCutout") {
      let channel = FlutterMethodChannel(name: "my.ttspot.app/cutout", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        CarCutout.handle(call, result: result)
      }
    }
    // Background location; Dart side: lib/core/location/background_location.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TTSpotBgLocation") {
      let channel = FlutterMethodChannel(name: "my.ttspot.app/bglocation", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        BackgroundLocation.shared.handle(call, result: result)
      }
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

// MARK: - Background location

/// "Share location when TT Spot is closed" (off by default; Mirrors BgLocationService.kt).
///
/// With "Always" permission: standard updates (~100 m accuracy, 75 m distance filter,
/// automotive, auto-pausing) while the process lives, plus significant-change
/// monitoring so iOS relaunches TT Spot in the background after it was closed.
/// Each fix goes to push_location_by_token with a per-phone token kept in the
/// Keychain. The Supabase session is never touched here, so nothing can log
/// the member out. The server answers "invalid" once the token is revoked,
/// which switches this off for good.
final class BackgroundLocation: NSObject, CLLocationManagerDelegate {
  static let shared = BackgroundLocation()

  private enum Key {
    static let enabled = "ttspot.bgloc.enabled"
    static let paused = "ttspot.bgloc.paused"
    static let url = "ttspot.bgloc.url"
    static let apiKey = "ttspot.bgloc.key"
    static let userId = "ttspot.bgloc.user"
    static let lastResult = "ttspot.bgloc.lastResult"
    static let lastAt = "ttspot.bgloc.lastAt"
    static let installId = "ttspot.bgloc.installId"
  }

  private let manager = CLLocationManager()
  private let defaults = UserDefaults.standard
  private var updating = false
  private var lastSent: CLLocation?
  private var lastSentAt: Date?
  private var pendingAuth: FlutterResult?
  private var authObservers: [NSObjectProtocol] = []
  private var promptShown = false

  private override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    manager.distanceFilter = 75
    manager.activityType = .automotiveNavigation
    manager.pausesLocationUpdatesAutomatically = true
  }

  // MARK: state

  private var isEnabled: Bool { defaults.bool(forKey: Key.enabled) && Keychain.token() != nil }
  private var isPaused: Bool { defaults.bool(forKey: Key.paused) }
  private var isAlways: Bool { manager.authorizationStatus == .authorizedAlways }

  private var installId: String {
    if let id = defaults.string(forKey: Key.installId) { return id }
    let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    defaults.set(id, forKey: Key.installId)
    return id
  }

  private var deviceLabel: String { "\(UIDevice.current.model) (\(installId.prefix(8)))" }

  /// App launch (including a background relaunch for a location event).
  func resumeIfEnabled() {
    // Relaunched before the first unlock after a reboot: settings and the
    // Keychain can't be read yet. Significant-change monitoring stays
    // registered with iOS, so the next wake-up after unlock picks it up.
    guard UIApplication.shared.isProtectedDataAvailable else { return }
    if !defaults.bool(forKey: Key.enabled) {
      // The Keychain outlives an uninstall; never reuse an old token.
      Keychain.delete()
      return
    }
    if !isPaused && isAlways { begin() }
  }

  private func begin() {
    guard isEnabled, !isPaused, isAlways else { return }
    manager.allowsBackgroundLocationUpdates = true
    manager.showsBackgroundLocationIndicator = true
    manager.startMonitoringSignificantLocationChanges()
    manager.startUpdatingLocation()
    updating = true
  }

  private func end() {
    manager.stopUpdatingLocation()
    manager.stopMonitoringSignificantLocationChanges()
    manager.allowsBackgroundLocationUpdates = false
    updating = false
  }

  private func forget(reason: String, revoke: Bool) {
    let token = Keychain.token()
    if revoke, let token = token {
      post("revoke_location_token", ["p_token": token], completion: nil)
    }
    end()
    Keychain.delete()
    defaults.set(false, forKey: Key.enabled)
    defaults.set(false, forKey: Key.paused)
    defaults.set(reason, forKey: Key.lastResult)
    defaults.set(Date().timeIntervalSince1970 * 1000, forKey: Key.lastAt)
  }

  // MARK: channel

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "status":
      result(status())
    case "start":
      guard let url = args["url"] as? String, !url.isEmpty,
            let key = args["key"] as? String, !key.isEmpty,
            let token = args["token"] as? String, !token.isEmpty,
            let userId = args["userId"] as? String, !userId.isEmpty else {
        result(FlutterError(code: "bad_args", message: "url, key, token and userId are required", details: nil))
        return
      }
      guard Keychain.set(token) else {
        result(FlutterError(code: "keychain", message: "Could not save the token", details: nil))
        return
      }
      defaults.set(url, forKey: Key.url)
      defaults.set(key, forKey: Key.apiKey)
      defaults.set(userId, forKey: Key.userId)
      defaults.set(true, forKey: Key.enabled)
      defaults.set(false, forKey: Key.paused)
      defaults.removeObject(forKey: Key.lastResult)
      defaults.removeObject(forKey: Key.lastAt)
      lastSent = nil
      lastSentAt = nil
      begin()
      result(updating)
    case "pause":
      defaults.set(true, forKey: Key.paused)
      end()
      result(nil)
    case "resume":
      defaults.set(false, forKey: Key.paused)
      begin()
      result(updating)
    case "stop":
      forget(reason: "off", revoke: (args["revoke"] as? Bool) ?? true)
      result(nil)
    case "requestBackground":
      requestAlways(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func status() -> [String: Any] {
    let s = manager.authorizationStatus
    let enabled = isEnabled
    let lastAt = defaults.double(forKey: Key.lastAt)
    let userId: Any = (enabled ? defaults.string(forKey: Key.userId) : nil) ?? NSNull()
    let lastResult: Any = defaults.string(forKey: Key.lastResult) ?? NSNull()
    return [
      "enabled": enabled,
      "paused": isPaused,
      "running": updating,
      "userId": userId,
      "lastResult": lastResult,
      "lastAt": lastAt > 0 ? NSNumber(value: Int64(lastAt)) : NSNull(),
      "background": s == .authorizedAlways,
      "foreground": s == .authorizedAlways || s == .authorizedWhenInUse,
      "device": deviceLabel,
    ]
  }

  /// Ask to upgrade "While Using" to "Always". iOS shows that prompt at most
  /// once; if nothing appears within a second, answer with the current status
  /// and Dart sends the member to Settings instead.
  private func requestAlways(_ result: @escaping FlutterResult) {
    let s = manager.authorizationStatus
    if s == .authorizedAlways { result(true); return }
    if s != .authorizedWhenInUse && s != .notDetermined { result(false); return }
    finishAuthRequest()
    pendingAuth = result
    promptShown = false
    let center = NotificationCenter.default
    authObservers = [
      center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
        self?.promptShown = true
      },
      center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
        self?.finishAuthRequest()
      },
    ]
    manager.requestAlwaysAuthorization()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self = self, !self.promptShown else { return }
      self.finishAuthRequest()
    }
  }

  private func finishAuthRequest() {
    authObservers.forEach { NotificationCenter.default.removeObserver($0) }
    authObservers = []
    guard let r = pendingAuth else { return }
    pendingAuth = nil
    r(isAlways)
  }

  // MARK: CLLocationManagerDelegate

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus != .notDetermined && pendingAuth != nil && !promptShown {
      finishAuthRequest()
    }
    if isAlways {
      if !updating { begin() }
    } else if updating {
      // Downgraded in Settings: stop, keep the token; the app shows a warning.
      end()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let loc = locations.last, isEnabled, !isPaused, let token = Keychain.token() else { return }
    // A wake-up from significant-change monitoring: run standard updates again too.
    if !updating { begin() }
    if loc.horizontalAccuracy < 0 || loc.horizontalAccuracy > 1000 { return }
    if let prev = lastSent, let at = lastSentAt, Date().timeIntervalSince(at) < 20, loc.distance(from: prev) < 50 { return }
    lastSent = loc
    lastSentAt = Date()
    var body: [String: Any] = [
      "p_token": token,
      "p_lat": loc.coordinate.latitude,
      "p_lng": loc.coordinate.longitude,
      "p_accuracy": loc.horizontalAccuracy,
    ]
    if loc.course >= 0 { body["p_heading"] = loc.course }
    if loc.speed >= 0 { body["p_speed"] = loc.speed }
    post("push_location_by_token", body) { [weak self] status in
      guard let self = self else { return }
      self.defaults.set(status ?? "error", forKey: Key.lastResult)
      self.defaults.set(Date().timeIntervalSince1970 * 1000, forKey: Key.lastAt)
      if status == "invalid" { self.forget(reason: "invalid", revoke: false) }
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if (error as? CLError)?.code == .denied { end() }
  }

  // MARK: network

  /// POST <url>/rest/v1/rpc/<fn> as anon (publishable key only). Wrapped in a
  /// background task so a ping started in the background gets to finish.
  private func post(_ fn: String, _ body: [String: Any], completion: ((String?) -> Void)?) {
    guard let base = defaults.string(forKey: Key.url),
          let key = defaults.string(forKey: Key.apiKey),
          let url = URL(string: (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/rest/v1/rpc/" + fn),
          let data = try? JSONSerialization.data(withJSONObject: body) else {
      completion?(nil)
      return
    }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    request.httpMethod = "POST"
    request.httpBody = data
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "apikey")
    // A legacy anon JWT also goes in Authorization; the new sb_publishable_ keys must not.
    if key.hasPrefix("eyJ") { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }

    let task = BackgroundTask()
    task.begin()
    URLSession.shared.dataTask(with: request) { data, response, _ in
      var status: String?
      if let data = data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        status = obj["status"] as? String
      }
      if status == nil, let code = (response as? HTTPURLResponse)?.statusCode { status = "http_\(code)" }
      DispatchQueue.main.async {
        completion?(status)
        task.end()
      }
    }.resume()
  }
}

/// A few seconds of background time for one request. Main thread only.
private final class BackgroundTask {
  private var id: UIBackgroundTaskIdentifier = .invalid

  func begin() {
    id = UIApplication.shared.beginBackgroundTask(withName: "ttspot.location") { [weak self] in
      self?.end()
    }
  }

  func end() {
    guard id != .invalid else { return }
    UIApplication.shared.endBackgroundTask(id)
    id = .invalid
  }
}

/// The per-phone location token, in the Keychain (this device only, readable
/// after the first unlock so a background relaunch can use it).
private enum Keychain {
  private static let service = "my.ttspot.app.bglocation"
  private static let account = "token"

  private static var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }

  static func set(_ value: String) -> Bool {
    delete()
    var q = query
    q[kSecValueData as String] = Data(value.utf8)
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
  }

  static func token() -> String? {
    var q = query
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete() {
    SecItemDelete(query as CFDictionary)
  }
}

// MARK: - Garage cut-outs

/// The car cut out of the member's own photo, on the phone: Vision's
/// foreground instance mask (iOS 17+), largest subject only. Mirrors
/// CarCutout.kt. "cutout" {bytes, maxSide} → {status, png?, areaRatio,
/// edgeLeft/Right/Top/Bottom, subjects, secondRatio, width, height}.
/// Older iOS answers "unsupported" and the garage shows the photo card.
enum CarCutout {
  private static let maxInput: CGFloat = 1600
  private static let queue = DispatchQueue(label: "my.ttspot.app.cutout", qos: .userInitiated)

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "cutout" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    guard let data = (args["bytes"] as? FlutterStandardTypedData)?.data else {
      result(FlutterError(code: "bad_args", message: "bytes are required", details: nil))
      return
    }
    let maxSide = (args["maxSide"] as? NSNumber)?.intValue ?? 1080
    guard #available(iOS 17.0, *) else {
      result(["status": "unsupported", "message": "needs iOS 17"])
      return
    }
    queue.async {
      let out = autoreleasepool { run(data, maxSide: maxSide) }
      DispatchQueue.main.async { result(out) }
    }
  }

  @available(iOS 17.0, *)
  private static func run(_ data: Data, maxSide: Int) -> [String: Any] {
    guard let image = UIImage(data: data), let photo = upright(image) else {
      return ["status": "error", "message": "can't read the photo"]
    }
    let handler = VNImageRequestHandler(cgImage: photo, orientation: .up, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    do {
      try handler.perform([request])
    } catch {
      return ["status": "error", "message": error.localizedDescription]
    }
    guard let obs = request.results?.first, !obs.allInstances.isEmpty else {
      return ["status": "no_subject", "subjects": 0]
    }

    // Instance labels per pixel (0 = background), at the mask's own resolution.
    let mask = obs.instanceMask
    CVPixelBufferLockBaseAddress(mask, .readOnly)
    let mw = CVPixelBufferGetWidth(mask)
    let mh = CVPixelBufferGetHeight(mask)
    let rowBytes = CVPixelBufferGetBytesPerRow(mask)
    guard mw > 0, mh > 0, let raw = CVPixelBufferGetBaseAddress(mask) else {
      CVPixelBufferUnlockBaseAddress(mask, .readOnly)
      return ["status": "error", "message": "empty mask"]
    }
    let base = raw.assumingMemoryBound(to: UInt8.self)
    var counts = [Int](repeating: 0, count: 256)
    var minX = [Int](repeating: Int.max, count: 256)
    var maxX = [Int](repeating: -1, count: 256)
    var minY = [Int](repeating: Int.max, count: 256)
    var maxY = [Int](repeating: -1, count: 256)
    for y in 0..<mh {
      let row = base + y * rowBytes
      for x in 0..<mw {
        let l = Int(row[x])
        if l == 0 { continue }
        counts[l] += 1
        if x < minX[l] { minX[l] = x }
        if x > maxX[l] { maxX[l] = x }
        if y < minY[l] { minY[l] = y }
        if y > maxY[l] { maxY[l] = y }
      }
    }
    let labels = obs.allInstances.filter { $0 > 0 && $0 < 256 }.sorted { counts[$0] > counts[$1] }
    guard let main = labels.first, counts[main] > 0 else {
      CVPixelBufferUnlockBaseAddress(mask, .readOnly)
      return ["status": "no_subject", "subjects": 0]
    }
    let second = labels.count > 1 ? counts[labels[1]] : 0

    // How much of each edge the subject runs into (share of rows / columns
    // with a subject pixel within 1 % of that edge).
    let bandX = max(1, Int((Double(mw) * 0.01).rounded()))
    let bandY = max(1, Int((Double(mh) * 0.01).rounded()))
    let label = UInt8(main)
    var left = 0, right = 0, top = 0, bottom = 0
    for y in 0..<mh {
      let row = base + y * rowBytes
      var l = false, r = false
      for k in 0..<min(bandX, mw) {
        if row[k] == label { l = true }
        if row[mw - 1 - k] == label { r = true }
      }
      if l { left += 1 }
      if r { right += 1 }
    }
    for x in 0..<mw {
      var t = false, b = false
      for k in 0..<min(bandY, mh) {
        if (base + k * rowBytes)[x] == label { t = true }
        if (base + (mh - 1 - k) * rowBytes)[x] == label { b = true }
      }
      if t { top += 1 }
      if b { bottom += 1 }
    }
    CVPixelBufferUnlockBaseAddress(mask, .readOnly)

    let sx = Double(photo.width) / Double(mw)
    let sy = Double(photo.height) / Double(mh)
    let boxW = Int((Double(maxX[main] - minX[main] + 1) * sx).rounded())
    let boxH = Int((Double(maxY[main] - minY[main] + 1) * sy).rounded())

    let png: Data
    do {
      let buffer = try obs.generateMaskedImage(ofInstances: IndexSet(integer: main), from: handler, croppedToInstancesExtent: true)
      let ci = CIImage(cvPixelBuffer: buffer)
      guard let cut = CIContext(options: nil).createCGImage(ci, from: ci.extent),
            let encoded = encode(cut, maxSide: maxSide) else {
        return ["status": "error", "message": "can't draw the cut-out"]
      }
      png = encoded
    } catch {
      return ["status": "error", "message": error.localizedDescription]
    }

    return [
      "status": "ok",
      "png": FlutterStandardTypedData(bytes: png),
      "areaRatio": Double(counts[main]) / Double(mw * mh),
      "edgeLeft": Double(left) / Double(mh),
      "edgeRight": Double(right) / Double(mh),
      "edgeTop": Double(top) / Double(mw),
      "edgeBottom": Double(bottom) / Double(mw),
      "subjects": labels.count,
      "secondRatio": Double(second) / Double(counts[main]),
      "width": boxW,
      "height": boxH,
    ]
  }

  /// The photo drawn upright (EXIF orientation applied), longest side at most 1600.
  private static func upright(_ image: UIImage) -> CGImage? {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return nil }
    let k = min(1, maxInput / max(size.width, size.height))
    if k == 1, image.imageOrientation == .up, let cg = image.cgImage { return cg }
    let target = CGSize(width: floor(size.width * k), height: floor(size.height * k))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }.cgImage
  }

  /// A little transparent room left, right and above the car, none below (the
  /// tyres sit on the PNG's bottom edge, so the bay can stand it on the floor
  /// and hang the reflection straight under it). Longest side at most maxSide, as PNG.
  private static func encode(_ cut: CGImage, maxSide: Int) -> Data? {
    let pad = max(2, CGFloat(max(cut.width, cut.height)) * 0.03)
    let pw = CGFloat(cut.width) + pad * 2
    let ph = CGFloat(cut.height) + pad
    let k = min(1, CGFloat(maxSide) / max(pw, ph))
    let size = CGSize(width: max(1, (pw * k).rounded()), height: max(1, (ph * k).rounded()))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    let rect = CGRect(x: pad * k, y: pad * k, width: CGFloat(cut.width) * k, height: CGFloat(cut.height) * k)
    return UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
      UIImage(cgImage: cut).draw(in: rect)
    }
  }
}
