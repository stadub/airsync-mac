//
//  ScrcpyServerManager.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-04-01.
//

import Foundation

@MainActor
final class ScrcpyServerManager: NSObject {
    static let shared = ScrcpyServerManager()

    private let serverLocalPath = Bundle.main.path(forResource: "scrcpy-server", ofType: nil) ?? "/Users/sameerasandakelum/GIT/airsync-mac/scrcpy-server"
    private let serverRemotePath = "/data/local/tmp/scrcpy-server"
    private let serverPort: Int = 1234
    // Isolate the native mirror from scrcpy windows launched for individual apps.
    private let serverSessionID = "0a175001"

    private var adbProcess: Process?
    private var sessionAudioEnabled = false
    private var sessionGeneration = UUID()
    private var startupRequest: MirrorStartupRequest?

    private let preparationQueue = DispatchQueue(label: "com.airsync.native-mirror-preparation")
    private var activeSerial: String?

    private func startServer(serial: String, desktopMode: Bool, request: MirrorStartupRequest,
                             completion: @escaping (Bool) -> Void) {
        guard !request.isCancelled else { return }
        activeSerial = serial
        let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) ?? "/opt/homebrew/bin/adb"
        let commands = [
            ["-s", serial, "forward", "--remove", "tcp:\(serverPort)"],
            ["-s", serial, "shell", "pkill -f '[c]om.genymobile.scrcpy.Server.*scid=\(serverSessionID)' || true"],
            ["-s", serial, "push", serverLocalPath, serverRemotePath],
            ["-s", serial, "forward", "tcp:\(serverPort)", "localabstract:scrcpy_\(serverSessionID)"]
        ]
        preparationQueue.async {
            var success = true
            for (index, arguments) in commands.enumerated() {
                guard !request.isCancelled else { return }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: adbPath)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    if index >= 2 && process.terminationStatus != 0 { success = false; break }
                } catch {
                    if index >= 2 { success = false; break }
                }
            }
            let prepared = success
            DispatchQueue.main.async {
                guard !request.isCancelled, self.startupRequest === request else { return }
                guard prepared else { completion(false); return }
                self.launchServer(serial: serial, desktopMode: desktopMode, completion: completion)
            }
        }
    }

    private var launchCompletion: ((Bool) -> Void)?
    private var launchTimer: Timer?

    func launchServer(serial: String, desktopMode: Bool = false, completion: @escaping (Bool) -> Void) {
        let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) ?? "/opt/homebrew/bin/adb"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)

        let audioOptions = MirrorPreferences().audioOptions
        sessionAudioEnabled = audioOptions.route.capturesAudio
        var serverArgs = [
            "scid=\(serverSessionID)", "tunnel_forward=true", "audio=\(sessionAudioEnabled)", "video=true", "control=true",
            "video_codec=h265", "video_bit_rate=8000000"
        ]

        if UserDefaults.standard.stayAwake {
            serverArgs += ["stay_awake=true", "keep_active=true"]
        }

        if sessionAudioEnabled {
            serverArgs.append("audio_codec=raw")
            serverArgs += ["audio_source=playback", "audio_dup=\(audioOptions.route.duplicatesOnPhone)"]
        }

        if desktopMode {
            // Virtual display — new_display requires "WxH" or "WxH/DPI" format
            let dpi = UserDefaults.standard.scrcpyDesktopDpi
            if !dpi.isEmpty {
                serverArgs.append("new_display=1920x1080/\(dpi)")
            } else {
                serverArgs.append("new_display=1920x1080")
            }
            serverArgs.append("flex_display=true")
        } else {
            serverArgs.append("max_size=1440")
        }

        process.arguments = [
            "-s", serial,
            "shell",
            "CLASSPATH=\(serverRemotePath)",
            "app_process", "/", "com.genymobile.scrcpy.Server", "4.1"
        ] + serverArgs

        self.adbProcess = process
        self.launchCompletion = completion

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    print("[scrcpy-server] \(trimmed)")

                    // Detect readiness: "[server] INFO: Video size: ..." or "[server] INFO: New display: ..."
                    if trimmed.contains("INFO: Video size:") || trimmed.contains("INFO: New display:") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            guard self?.adbProcess === process else { return }
                            self?.launchTimer?.invalidate()
                            self?.launchTimer = nil
                            let callback = self?.launchCompletion
                            self?.launchCompletion = nil
                            callback?(true)
                        }
                    }

                    // Detect failure
                    if trimmed.contains("ERROR:") || trimmed.contains("Exception") {
                        print("[ScrcpyServerManager] Server reported error: \(trimmed)")
                        // Trigger failure if it's a critical error
                        if trimmed.contains("Permission denied") || trimmed.contains("could not start") {
                            DispatchQueue.main.async {
                                guard self?.adbProcess === process else { return }
                                let callback = self?.launchCompletion
                                self?.launchCompletion = nil
                                callback?(false)
                            }
                        }
                    }
                }
            }
        }

        do {
            try process.run()

            // Watchdog timer: if we don't see the log in 5s, proceed anyway
            self.launchTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                guard self?.adbProcess === process else { return }
                if let completion = self?.launchCompletion {
                    print("[ScrcpyServerManager] Readiness log timeout - proceeding anyway")
                    self?.launchCompletion = nil
                    completion(process.isRunning)
                }
            }
        } catch {
            self.launchCompletion = nil
            print("[ScrcpyServerManager] Launch failed: \(error)")
            completion(false)
        }
    }

    func stopServer() {
        launchTimer?.invalidate()
        launchTimer = nil
        launchCompletion = nil
        if let process = adbProcess {
            DispatchQueue.main.async { KeyboardLayoutSync.shared.remove(processID: process.processIdentifier) }
            if let pipe = process.standardOutput as? Pipe {
                pipe.fileHandleForReading.readabilityHandler = nil
            }
            if let pipe = process.standardError as? Pipe {
                pipe.fileHandleForReading.readabilityHandler = nil
            }
            if process.isRunning { process.terminate() }
        }
        adbProcess = nil

        // Serialize cleanup with preparation so a cancelled forward cannot survive
        // or remove a replacement session's forward.
        guard let serial = activeSerial else { return }
        activeSerial = nil
        let port = serverPort
        let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) ?? "/opt/homebrew/bin/adb"
        preparationQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adbPath)
            process.arguments = ["-s", serial, "forward", "--remove", "tcp:\(port)"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run(); process.waitUntilExit() }
            catch { print("[ScrcpyServerManager] Failed to remove port forward: \(error)") }
        }
    }

    func startMirroringSession(appState: AppState, streamClient: ScrcpyStreamClient, desktopMode: Bool = false, completion: @escaping (Bool, String?) -> Void) {
        // Stop any current session first to prevent port/process clashes
        self.stopMirroringSession(streamClient: streamClient)

        // All lifecycle transitions are on the main actor. Deliver completion
        // in that same turn so a cancelled session cannot publish late success.
        let request = MirrorStartupRequest(completion: completion)
        startupRequest = request
        let generation = sessionGeneration
        let mappedSerial = appState.selectedWiredSerial ?? (appState.device?.deviceId).flatMap { appState.deviceAdbSerials[$0] }
        let hasWirelessAddress = !appState.adbConnectedIP.isEmpty
        let wiredAdbEnabled = appState.wiredAdbEnabled
        let wirelessAddress = "\(appState.adbConnectedIP):\(appState.adbPort)"
        let adbConnected = appState.adbConnected

        ADBConnector.getWiredDevices { devices in
            DispatchQueue.main.async {
                guard !request.isCancelled, self.startupRequest === request else { return }
                let serialToUse: String?
                if let mapped = mappedSerial, devices.contains(where: { $0.serial == mapped }) {
                    serialToUse = mapped
                } else {
                    serialToUse = devices.first?.serial
                }

                let finalSerial: String?
                if wiredAdbEnabled, let serial = serialToUse {
                    finalSerial = serial
                } else if adbConnected && hasWirelessAddress {
                    finalSerial = wirelessAddress
                } else {
                    finalSerial = nil
                }

                guard let serial = finalSerial else {
                    request.finish(false, error: "No ADB device detected. Please connect your device via USB or Wi-Fi.")
                    return
                }

                self.startServer(serial: serial, desktopMode: desktopMode, request: request) { success in
                    guard success else {
                        self.stopServer()
                        request.finish(false, error: "Failed to start scrcpy server on device.")
                        return
                    }
                    DispatchQueue.main.async {
                        guard !request.isCancelled, self.startupRequest === request else { return }
                        streamClient.onPacketReceived = { data, isConfig, isKeyframe, pts in
                            ScrcpyVideoDecoder.shared.decodePacket(data: data, isConfig: isConfig, pts: pts)
                        }
                        let openControl = { [weak self] in
                            guard let self, self.sessionGeneration == generation else { return }
                            ScrcpyControlClient.shared.connect(onKeyboardReady: { [weak self] in
                                guard let self, self.sessionGeneration == generation, let process = self.adbProcess else { return }
                                let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) ?? "/opt/homebrew/bin/adb"
                                KeyboardLayoutSync.shared.register(process: process, adbPath: adbPath, serial: serial)
                            })
                        }
                        streamClient.connect(onTransportReady: { [weak self] in
                            guard let self, self.sessionGeneration == generation else { return }
                            if self.sessionAudioEnabled {
                                ScrcpyAudioClient.shared.connect(onSocketReady: openControl)
                            } else { openControl() }
                        })
                        request.finish(true)
                    }
                }
            }
        }
    }

    func stopMirroringSession(streamClient: ScrcpyStreamClient) {
        startupRequest?.cancel()
        startupRequest = nil
        sessionGeneration = UUID()
        ScrcpyAudioClient.shared.disconnect()
        streamClient.disconnect()
        ScrcpyControlClient.shared.disconnect()
        self.stopServer()
    }
}
