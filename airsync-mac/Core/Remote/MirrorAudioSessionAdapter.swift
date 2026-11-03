import Foundation

@MainActor
struct AppMirrorAudioSessions: MirrorAudioSessionControlling {
    var hasNativeSession: Bool {
        let state = AppState.shared
        return state.isSidebarMirroring || state.isNativeMirroring || state.isNativeDesktopMirroring
    }
    func restartExternal(completion: @escaping (String?) -> Void) {
        ADBConnector.restartMirrorWindowsForAudio(completion: completion)
    }
    func restartNative(completion: @escaping (Bool, String?) -> Void) {
        let state = AppState.shared
        ScrcpyServerManager.shared.startMirroringSession(
            appState: state, streamClient: ScrcpyStreamClient.shared,
            desktopMode: state.isNativeDesktopMirroring, completion: completion
        )
    }
}

extension MirrorAudioRouting {
    static let shared = MirrorAudioRouting(sessions: AppMirrorAudioSessions())
}
