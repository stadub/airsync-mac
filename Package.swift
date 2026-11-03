// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AirSyncMirroringCore", platforms: [.macOS(.v14)], targets: [
    .target(name: "MirroringCore", path: "airsync-mac/Core/Mirroring", sources: ["WirelessReconnectPlan.swift"]),
    .testTarget(name: "MirroringCoreTests", dependencies: ["MirroringCore"], path: "Tests/MirroringCoreTests")
])
