// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AirSyncMirroringCore", platforms: [.macOS(.v14)], targets: [
    .target(name: "MirroringCore", path: "airsync-mac/Core/Mirroring", sources: ["WirelessReconnectPlan.swift", "MirrorAudioRouting.swift", "MirrorPreferences.swift", "MirrorStartupRequest.swift", "ExternalMirrorRegistry.swift", "ProcessOutputCapture.swift"]),
    .testTarget(name: "MirroringCoreTests", dependencies: ["MirroringCore"], path: "Tests/MirroringCoreTests")
])
