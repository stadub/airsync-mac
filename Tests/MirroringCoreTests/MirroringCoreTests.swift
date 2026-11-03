import XCTest
@testable import MirroringCore

final class MirroringCoreTests: XCTestCase {
    func testCancelledStartupCompletesExactlyOnce() {
        var outcomes: [Bool] = []
        let request = MirrorStartupRequest { success, _ in outcomes.append(success) }
        request.cancel()
        // A delayed discovery/readiness callback must not adopt a new session.
        if !request.isCancelled { XCTFail("Cancelled startup may not launch") }
        request.finish(true)
        request.cancel()
        XCTAssertEqual(outcomes, [false])
    }

    func testAudioRoutesReplaceOldFlagsWithoutChangingDisplayOptions() {
        let original = ["-s", "device", "--new-display=1920x1080", "--no-audio", "--audio-dup", "--audio-buffer=10"]
        for route in AudioRoute.allCases {
            let args = MirrorAudioOptions(route: route, bufferMilliseconds: 200).applying(to: original)
            XCTAssertTrue(args.contains("--new-display=1920x1080"))
            XCTAssertEqual(args.contains("--no-audio"), route == .phone)
            XCTAssertEqual(args.contains("--audio-dup"), route == .both)
            XCTAssertEqual(args.contains("--audio-buffer=200"), route != .phone)
            XCTAssertFalse(args.contains("--audio-buffer=10"))
        }
        XCTAssertEqual(MirrorAudioOptions(route: .mac, bufferMilliseconds: 0).bufferMilliseconds, 60)
        XCTAssertEqual(MirrorAudioOptions(route: .mac, bufferMilliseconds: 999).bufferMilliseconds, 500)
    }

    func testPreferencesAndProfilesRemainIndependent() {
        let suite = "AirSyncTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MirrorPreferences(defaults: defaults)
        XCTAssertEqual(preferences.audioOptions.route, .both)
        for route in AudioRoute.allCases {
            preferences.setAudioRoute(route)
            XCTAssertEqual(preferences.audioOptions.route, route)
        }
        defaults.set("home,back", forKey: MirrorProfile.phone.navigationOrderKey)
        defaults.set("back,home", forKey: MirrorProfile.desktop.navigationOrderKey)
        XCTAssertEqual(defaults.string(forKey: MirrorProfile.phone.navigationOrderKey), "home,back")
    }

    func testReconnectAdoptsLiveTransportUnlessResetIsExplicit() {
        let normal = WirelessReconnectPlan(livePort: 40000, reportedPorts: ["39000"], resetServer: false)
        XCTAssertEqual(normal.reusePort, 40000)
        XCTAssertFalse(normal.resetServer)
        let reset = WirelessReconnectPlan(livePort: 40000, reportedPorts: ["39000", "40000"], resetServer: true)
        XCTAssertNil(reset.reusePort)
        XCTAssertEqual(reset.candidatePorts, ["40000", "39000"])
        let disconnected = WirelessReconnectPlan(livePort: nil, reportedPorts: ["39000"], resetServer: false)
        XCTAssertNil(disconnected.reusePort)
        XCTAssertEqual(disconnected.candidatePorts, ["39000"])
    }



    func testCloseDuringAudioRestartDoesNotRelaunch() {
        let launched = expectation(description: "launched")
        let stopped = expectation(description: "restart stopping")
        let restarted = expectation(description: "restart completed")
        let closed = expectation(description: "closed")
        let releaseStop = DispatchSemaphore(value: 0)
        let fake = FakeProcess()
        fake.onStop = { stopped.fulfill(); _ = releaseStop.wait(timeout: .now() + 3) }
        var launches = 0
        let registry = ExternalMirrorRegistry(factory: { _ in launches += 1; return fake })
        registry.launch(configuration()) { error in XCTAssertNil(error); launched.fulfill() }
        wait(for: [launched], timeout: 3)
        registry.restartAudio(MirrorAudioOptions(route: .mac, bufferMilliseconds: 200)) { error in
            XCTAssertNil(error); restarted.fulfill()
        }
        wait(for: [stopped], timeout: 3)
        registry.closeScreenMirrors { closed.fulfill() }
        releaseStop.signal()
        wait(for: [restarted, closed], timeout: 3)
        XCTAssertEqual(launches, 1)
    }

    func testChattyProcessExitsAndRetainsBoundedLogTail() throws {
        let exited = expectation(description: "chatty process exited")
        let process = FoundationMirrorProcess(configuration: configuration(
            executable: "/bin/sh", arguments: ["-c", "head -c 2097152 /dev/zero; printf END"]
        ))
        try process.start { status, output in
            XCTAssertEqual(status, 0)
            XCTAssertLessThanOrEqual(output.utf8.count, 65_536)
            XCTAssertTrue(output.hasSuffix("END"))
            exited.fulfill()
        }
        wait(for: [exited], timeout: 5)
        if process.isRunning { process.stop() }
    }

    @MainActor
    func testAudioRoutingWaitsForBothSessionsAndReportsFailure() async {
        let suite = "AirSyncRoutingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let sessions = FakeAudioSessions()
        let routing = MirrorAudioRouting(sessions: sessions, preferences: MirrorPreferences(defaults: defaults))
        routing.select(.mac)
        XCTAssertTrue(routing.isChanging)
        XCTAssertEqual(MirrorPreferences(defaults: defaults).audioOptions.route, .mac)
        // A second selection must not schedule overlapping restarts.
        routing.select(.both)
        XCTAssertEqual(sessions.externalRestarts, 1)
        sessions.externalCompletion?("External restart failed")
        XCTAssertTrue(routing.isChanging)
        sessions.nativeCompletion?(true, nil)
        // The controller publishes completion on the next main-queue turn.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertFalse(routing.isChanging)
        XCTAssertEqual(routing.error, "External restart failed")
    }

    private func configuration(executable: String = "/unused", arguments: [String] = []) -> MirrorLaunchConfiguration {
        MirrorLaunchConfiguration(executable: executable, arguments: arguments, environment: nil, serial: "test", followKeyboard: false)
    }
}

private final class FakeProcess: MirrorManagedProcess, @unchecked Sendable {
    var identifier: Int32 { 123 }
    var foundationProcess: Process? { nil }
    var isRunning = false
    var onStop: (() -> Void)?
    private var onExit: ((Int32, String) -> Void)?
    func start(onExit: @escaping (Int32, String) -> Void) throws { self.onExit = onExit; isRunning = true }
    func stop() { onStop?(); isRunning = false; onExit?(0, "") }
}

@MainActor
private final class FakeAudioSessions: MirrorAudioSessionControlling {
    var hasNativeSession = true
    var externalRestarts = 0
    var externalCompletion: ((String?) -> Void)?
    var nativeCompletion: ((Bool, String?) -> Void)?
    func restartExternal(completion: @escaping (String?) -> Void) {
        externalRestarts += 1
        externalCompletion = completion
    }
    func restartNative(completion: @escaping (Bool, String?) -> Void) { nativeCompletion = completion }
}
