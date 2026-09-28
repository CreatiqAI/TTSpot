// swift-tools-version: 5.9
// Flutter looks for Package.swift at ios/<plugin_name>/Package.swift
import PackageDescription

let package = Package(
    name: "flutter_mapbox",
    platforms: [.iOS("14.0")],
    products: [
        .library(name: "flutter-mapbox", targets: ["flutter_mapbox"])
    ],
    dependencies: [
        // Flutter injects this local package during build
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // TT Spot patch: exact 3.31.1 because mapbox_maps_flutter 2.31.1 pins
        // mapbox-maps-ios exactly to 11.31.1 and the navigation SDK pins the
        // same maps version; two different exact pins cannot resolve together.
        .package(
            url: "https://github.com/mapbox/mapbox-navigation-ios.git",
            exact: "3.31.1"
        )
    ],
    targets: [
        .target(
            name: "flutter_mapbox",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "MapboxNavigationCore", package: "mapbox-navigation-ios"),
                .product(name: "MapboxNavigationUIKit", package: "mapbox-navigation-ios")
            ],
            // Sources/flutter_mapbox is a symlink to ios/Classes
            // Exclude ObjC files — SPM targets must be single-language
            exclude: [
                "FlutterMapboxPlugin.m",
                "FlutterMapboxPlugin.h"
            ]
        )
    ]
)
