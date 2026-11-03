import Foundation

nonisolated enum MirrorProfile {
    case phone, desktop
    var headerVisibleKey: String { self == .desktop ? "desktopHeaderVisibleButtons" : "embeddedHeaderVisibleButtons" }
    var headerOrderKey: String { self == .desktop ? "desktopHeaderButtonOrder" : "embeddedHeaderButtonOrder" }
    var navigationButtonsKey: String { self == .desktop ? "desktopNavigationButtons" : "embeddedNavigationButtons" }
    var navigationOrderKey: String { self == .desktop ? "desktopNavigationOrder" : "embeddedNavigationOrder" }
    var controlsKey: String { self == .desktop ? "showDesktopMirrorControls" : "showMirrorControls" }
    var navigationEnabledKey: String { self == .desktop ? "showDesktopMirrorNavigation" : "showEmbeddedMirrorNavigation" }
}

nonisolated enum AudioRoute: String, CaseIterable {
    case phone, mac, both
    var capturesAudio: Bool { self != .phone }
    var duplicatesOnPhone: Bool { self == .both }
}

nonisolated struct MirrorAudioOptions {
    let route: AudioRoute
    let bufferMilliseconds: Int

    init(route: AudioRoute, bufferMilliseconds: Int) {
        self.route = route
        self.bufferMilliseconds = min(500, max(60, bufferMilliseconds))
    }

    func applying(to arguments: [String]) -> [String] {
        var result = arguments.filter {
            $0 != "--no-audio" && $0 != "--audio-dup" &&
                !$0.hasPrefix("--audio-source=") && !$0.hasPrefix("--audio-buffer=")
        }
        guard route.capturesAudio else { return result + ["--no-audio"] }
        result += ["--audio-source=playback", "--audio-buffer=\(bufferMilliseconds)"]
        if route.duplicatesOnPhone { result.append("--audio-dup") }
        return result
    }
}

nonisolated struct MirrorPreferences {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var audioOptions: MirrorAudioOptions {
        let route: AudioRoute = defaults.bool(forKey: "noAudio") ? .phone :
            ((defaults.object(forKey: "keepPhoneAudio") as? Bool ?? true) ? .both : .mac)
        return MirrorAudioOptions(route: route, bufferMilliseconds: Int(defaults.object(forKey: "phoneAudioBufferMS") as? Double ?? 200))
    }

    func setAudioRoute(_ route: AudioRoute) {
        defaults.set(!route.capturesAudio, forKey: "noAudio")
        defaults.set(route != .mac, forKey: "keepPhoneAudio")
    }
}
