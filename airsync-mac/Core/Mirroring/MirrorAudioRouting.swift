import Foundation
import Combine

/// Callbacks are delivered on the main queue, like the UI that owns this controller.
@MainActor
protocol MirrorAudioSessionControlling {
    var hasNativeSession: Bool { get }
    func restartExternal(completion: @escaping (String?) -> Void)
    func restartNative(completion: @escaping (Bool, String?) -> Void)
}

/// Shared by the menu bar and the embedded mirror header.
@MainActor
final class MirrorAudioRouting: ObservableObject {
    private let sessions: MirrorAudioSessionControlling
    private let preferences: MirrorPreferences

    init(sessions: MirrorAudioSessionControlling, preferences: MirrorPreferences = MirrorPreferences()) {
        self.sessions = sessions
        self.preferences = preferences
    }
    @Published private(set) var isChanging = false
    @Published private(set) var error: String?

    func select(_ route: AudioRoute) {
        guard !isChanging else { return }
        preferences.setAudioRoute(route)
        error = nil
        isChanging = true
        let restarts = DispatchGroup()
        restarts.enter()
        sessions.restartExternal { [self] failure in
            if let failure { error = failure }
            restarts.leave()
        }
        if sessions.hasNativeSession {
            restarts.enter()
            sessions.restartNative { [self] success, failure in
                if !success { error = failure ?? "Could not reconnect the mirror." }
                restarts.leave()
            }
        }
        restarts.notify(queue: .main) { [self] in isChanging = false }
    }
}
