import Flutter
import UIKit
import MapboxMaps
import MapboxDirections
import MapboxNavigationCore
import MapboxNavigationUIKit

@objc(FlutterMapboxPlugin)
public class SwiftFlutterMapboxPlugin: NavigationFactory, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_mapbox", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "flutter_mapbox/events", binaryMessenger: registrar.messenger())
        // TT Spot patch: full-screen navigation presents from this registrar's
        // view controller (see NavigationHost in NavigationFactory.swift).
        NavigationHost.registrar = registrar
        let instance = SwiftFlutterMapboxPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
        let viewFactory = FlutterMapboxViewFactory(messenger: registrar.messenger())
        registrar.register(viewFactory, withId: "FlutterMapboxView")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? NSDictionary
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "getDistanceRemaining":
            result(_distanceRemaining)
        case "getDurationRemaining":
            result(_durationRemaining)
        case "startNavigation":
            startNavigation(arguments: arguments, result: result)
        case "finishNavigation":
            endNavigation(result: result)
        case "enableOfflineRouting":
            downloadOfflineRoute(arguments: arguments, flutterResult: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
