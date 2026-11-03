// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirSyncMirroringCore",
    platforms: [.macOS(.v14)],
    products: [],
    targets: [
        .target(name: "MirroringCore", path: "airsync-mac/Core/Mirroring",
                sources: ["MirrorAudioRouting.swift", "MirrorStartupRequest.swift", "MirrorPreferences.swift", "MirrorButtonLayout.swift",
                          "ProcessOutputCapture.swift", "ExternalMirrorRegistry.swift", "WirelessReconnectPlan.swift"]),
        .target(name: "MirroringUI", path: "airsync-mac/Screens/Remote",
                exclude: ["FloatingNavbar.swift", "MirrorButtonEditor.swift", "MirrorLayoutEditorWindow.swift", "MirrorNavigationBar.swift", "MirrorWindowControls.swift", "NativeDesktopMirrorView.swift", "NavbarWindowController.swift", "NonFocusableWindow.swift", "PhoneMirrorHeader.swift", "ScrcpyBaseMirrorView.swift", "ScrcpyMirrorView.swift", "SideControlBar.swift", "SideControlWindowController.swift"], sources: ["MirrorDragRegion.swift"]),
        .testTarget(name: "MirroringCoreTests", dependencies: ["MirroringCore", "MirroringUI"], path: "Tests/MirroringCoreTests")
    ]
)
