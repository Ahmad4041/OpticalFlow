// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpticalFlow",
    platforms: [.macOS(.v26)],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "OpticalFlowKit"),
        .executableTarget(
            name: "OpticalFlow",
            dependencies: ["OpticalFlowKit"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "OpticalFlowKitTests", dependencies: ["OpticalFlowKit"]),
    ]
)
