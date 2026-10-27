//
//  ADBConnector.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-01.
//

import Foundation
import AppKit

struct WiredADBDevice: Hashable, Identifiable {
    var id: String { serial }
    let serial: String
    let model: String
}

struct ADBConnector {

    private struct MirrorWindow {
        let process: Process
        let executable: String
        let arguments: [String]
        let environment: [String: String]?
        let serial: String
        let followKeyboard: Bool
    }
    private static let mirrorLock = NSLock()
    private static var mirrorWindows: [Int32: MirrorWindow] = [:]
    private static var restartingWindows: Set<Int32> = []

    private static func isScreenMirror(_ window: MirrorWindow) -> Bool {
        !window.arguments.contains(where: { $0.hasPrefix("--new-display") || $0.hasPrefix("--start-app=") })
    }

    private static func updateScreenMirrorState() {
        DispatchQueue.main.async {
            mirrorLock.lock()
            let count = mirrorWindows.values.filter { $0.process.isRunning && isScreenMirror($0) }.count
            mirrorLock.unlock()
            AppState.shared.externalScreenMirrorCount = count
        }
    }

    static func closeScreenMirrorWindows(completion: @escaping () -> Void = {}) {
        mirrorLock.lock()
        let windows = mirrorWindows.values.filter { $0.process.isRunning && isScreenMirror($0) }
        for window in windows { restartingWindows.insert(window.process.processIdentifier) }
        mirrorLock.unlock()
        DispatchQueue.global(qos: .userInitiated).async {
            for window in windows {
                if window.process.isRunning { window.process.terminate() }
                window.process.waitUntilExit()
            }
            updateScreenMirrorState()
            DispatchQueue.main.async { completion() }
        }
    }

    /// Relaunch only windows owned by AirSync, preserving their launch options.
    static func restartMirrorWindowsForAudio(completion: @escaping (String?) -> Void) {
        let noAudio = UserDefaults.standard.noAudio
        let duplicate = UserDefaults.standard.object(forKey: "keepPhoneAudio") as? Bool ?? true
        let buffer = Int(min(500, max(60, UserDefaults.standard.object(forKey: "phoneAudioBufferMS") as? Double ?? 200)))
        mirrorLock.lock()
        let windows = mirrorWindows.values.filter { $0.process.isRunning }
        for window in windows { restartingWindows.insert(window.process.processIdentifier) }
        mirrorLock.unlock()
        DispatchQueue.global(qos: .userInitiated).async {
            var errors: [String] = []
            for window in windows {
                if window.process.isRunning { window.process.terminate() }
                window.process.waitUntilExit()
                var args = window.arguments.filter {
                    $0 != "--no-audio" && $0 != "--audio-dup" && !$0.hasPrefix("--audio-source=") && !$0.hasPrefix("--audio-buffer=")
                }
                if noAudio { args.append("--no-audio") }
                else {
                    args += ["--audio-source=playback", "--audio-buffer=\(buffer)"]
                    if duplicate { args.append("--audio-dup") }
                }
                do {
                    try launchMirrorWindow(executable: window.executable, arguments: args,
                                           environment: window.environment, serial: window.serial,
                                           followKeyboard: window.followKeyboard)
                } catch { errors.append(error.localizedDescription) }
            }
            DispatchQueue.main.async { completion(errors.isEmpty ? nil : errors.joined(separator: "\n")) }
        }
    }

    private static func launchMirrorWindow(executable: String, arguments: [String], environment: [String: String]?, serial: String, followKeyboard: Bool) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.environment = environment
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.terminationHandler = { process in
            mirrorLock.lock()
            mirrorWindows.removeValue(forKey: process.processIdentifier)
            let intentional = restartingWindows.remove(process.processIdentifier) != nil
            mirrorLock.unlock()
            updateScreenMirrorState()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                KeyboardLayoutSync.shared.remove(processID: process.processIdentifier)
                MirrorWindowControls.shared.removeExternal(processID: process.processIdentifier)
                guard !intentional else { return }
                AppState.shared.adbConnectionResult = "scrcpy exited:\n" + output
                if process.terminationStatus != 0 {
                    let lower = output.lowercased()
                    if lower.contains("unauthorized") || lower.contains("auth") || lower.contains("pair") {
                        presentScrcpyPairingAlert(title: "Device Not Paired", informative: "Please pair or authorize your Android device with this Mac.")
                    } else {
                        presentScrcpyAlert(title: "Mirroring Ended With Errors", informative: "See ADB Console for details.")
                    }
                }
            }
        }
        // Hold the lock until registration so an immediately exiting child cannot leave a stale entry.
        mirrorLock.lock()
        do { try task.run() }
        catch { mirrorLock.unlock(); throw error }
        mirrorWindows[task.processIdentifier] = MirrorWindow(process: task, executable: executable, arguments: arguments, environment: environment, serial: serial, followKeyboard: followKeyboard)
        mirrorLock.unlock()
        updateScreenMirrorState()
        if !arguments.contains(where: { $0.hasPrefix("--new-display") || $0.hasPrefix("--start-app=") }) {
            DispatchQueue.main.async { MirrorWindowControls.shared.addExternal(process: task, serial: serial) }
        }
        if followKeyboard, let adbPath = environment?["ADB"] {
            DispatchQueue.main.async {
                guard task.isRunning else { return }
                KeyboardLayoutSync.shared.register(process: task, adbPath: adbPath, serial: serial)
            }
        }
    }

    static func performMirrorControl(_ action: EmbeddedNavigationAction, serial: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let adb = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else { return }
            func run(_ args: [String]) -> String {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: adb)
                task.arguments = ["-s", serial, "shell"] + args
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = FileHandle.nullDevice
                do {
                    try task.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    task.waitUntilExit()
                    return String(data: data, encoding: .utf8) ?? ""
                } catch { return "" }
            }
            if let keycode = action.keycode { _ = run(["input", "keyevent", String(keycode)]) }
            else {
                switch action {
                case .notifications: _ = run(["cmd", "statusbar", "expand-notifications"])
                case .quickSettings: _ = run(["cmd", "statusbar", "expand-settings"])
                case .collapsePanels: _ = run(["cmd", "statusbar", "collapse"])
                case .rotateDevice:
                    let current = Int(run(["settings", "get", "system", "user_rotation"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    _ = run(["wm", "user-rotation", "lock", String((current + 1) % 4)])
                default: break
                }
            }
        }
    }

    // Potential fallback paths
    static let possibleADBPaths: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ]
    }()
    static let possibleScrcpyPaths = [
        "/opt/scrcpy/scrcpy",
        "/opt/homebrew/bin/scrcpy",
        "/usr/local/bin/scrcpy"
    ]
    
    // Flag to prevent concurrent connection attempts
    private static var isConnecting = false
    private static let connectionLock = NSLock()

    // Try to locate a binary
    static func findExecutable(named name: String, fallbackPaths: [String]) -> String? {
        // Step 1: Try direct execution from PATH
        if isExecutableAvailable(name) {
            logBinaryDetection("\(name) found in system PATH — using direct command.")
            let path = getExecutablePath(name)
            return path
        }

        // Step 2: Try fallback paths
        for path in fallbackPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                logBinaryDetection("\(name) found at \(path) — using fallback path.")
                return path
            }
        }

        logBinaryDetection("\(name) not found in PATH or fallback locations.")
        return nil
    }

    private static func getExecutablePath(_ name: String) -> String {
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = [name]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output
    }
    // Check if binary is available in PATH
    static func isExecutableAvailable(_ name: String) -> Bool {
        let data = getExecutablePath(name)
        return !data.isEmpty
    }

    static func logBinaryDetection(_ message: String) {
        DispatchQueue.main.async {
            AppState.shared.adbConnectionResult = (AppState.shared.adbConnectionResult ?? "") + "\n[Binary Detection] \(message)"
        }
        print("[adb-connector] (Binary Detection) \(message)")
    }
    
    static func getWiredDevices(completion: @escaping ([WiredADBDevice]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else {
                completion([])
                return
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adbPath)
            process.arguments = ["devices", "-l"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let lines = output.components(separatedBy: .newlines)
                
                var devices: [WiredADBDevice] = []
                for line in lines {
                    let parts = line.split(separator: " ").filter { !$0.isEmpty }
                    if parts.count >= 2 && parts[1] == "device" {
                        let serial = String(parts[0])
                        if !serial.contains(":") {
                            var model = "Unknown Device"
                            for part in parts {
                                if part.hasPrefix("model:") {
                                    model = part.replacingOccurrences(of: "model:", with: "").replacingOccurrences(of: "_", with: " ")
                                    break
                                }
                            }
                            devices.append(WiredADBDevice(serial: serial, model: model))
                        }
                    }
                }
                completion(devices)
            } catch {
                print("[adb-connector] Error getting wired devices: \(error)")
                completion([])
            }
        }
    }
    
    static func getWiredDeviceSerial(completion: @escaping (String?) -> Void) {
        getWiredDevices { devices in
            if let first = devices.first {
                logBinaryDetection("Detected wired ADB device: \(first.serial)")
                completion(first.serial)
            } else {
                completion(nil)
            }
        }
    }

    private static func clearConnectionFlag() {
        connectionLock.lock()
        isConnecting = false
        connectionLock.unlock()
    }

    static func connectToADB(ip: String, killServer: Bool = false) {
        connectionLock.lock()
        if isConnecting {
            connectionLock.unlock()
            logBinaryDetection("ADB connection already in progress, ignoring duplicate request")
            return
        }
        isConnecting = true
        connectionLock.unlock()
        
        DispatchQueue.main.async {
            AppState.shared.adbConnecting = true
            let reportedPorts = AppState.shared.device?.adbPorts ?? []
            // Reuse the saved port only for the same host and only when none was reported.
            let devicePorts = reportedPorts.isEmpty && AppState.shared.adbConnectedIP == ip
                ? [String(AppState.shared.adbPort)] : reportedPorts
            let fallbackToMdns = AppState.shared.fallbackToMdns

            DispatchQueue.global(qos: .userInitiated).async {
                guard let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else {
                    DispatchQueue.main.async {
                        AppState.shared.adbConnectionResult = "ADB not found. Please install via Homebrew: brew install android-platform-tools"
                        AppState.shared.adbConnected = false
                        AppState.shared.adbConnecting = false
                    }
                    clearConnectionFlag()
                    return
                }

                if killServer {
                    logBinaryDetection("Manual connection requested. Killing ADB server first...")
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: adbPath)
                    process.arguments = ["kill-server"]
                    try? process.run()
                    process.waitUntilExit()
                    logBinaryDetection("ADB server killed.")
                }

                // The phone app may cache an old debugging port. Prefer a live,
                // authorized ADB transport for the exact same host when available.
                if let port = connectedWirelessPort(adbPath: adbPath, ip: ip) {
                    DispatchQueue.main.async {
                        clearConnectionFlag()
                        AppState.shared.adbConnectedIP = ip
                        AppState.shared.adbPort = port
                        AppState.shared.adbConnectionMode = .wireless
                        AppState.shared.adbConnecting = false
                        AppState.shared.adbConnectionResult = "Using connected wireless device at \(ip):\(port)"
                        AppState.shared.adbConnected = true
                    }
                    return
                }

                if devicePorts.isEmpty {
                    if fallbackToMdns {
                        logBinaryDetection("Device reported no ADB ports, attempting mDNS discovery...")
                        discoverADBPorts(adbPath: adbPath, ip: ip) { ports in
                            if ports.isEmpty {
                                logBinaryDetection("mDNS discovery found no ports for \(ip).")
                                DispatchQueue.main.async {
                                    AppState.shared.adbConnected = false
                                    AppState.shared.adbConnecting = false
                                    AppState.shared.adbConnectionResult = "No ADB ports reported by device and mDNS discovery failed."
                                }
                                clearConnectionFlag()
                            } else {
                                logBinaryDetection("mDNS discovery found ports: \(ports.map(String.init).joined(separator: ", "))")
                                self.proceedWithConnection(adbPath: adbPath, ip: ip, portsToTry: ports)
                            }
                        }
                    } else {
                        logBinaryDetection("Device reported no ADB ports and mDNS fallback is disabled.")
                        DispatchQueue.main.async {
                            AppState.shared.adbConnected = false
                            AppState.shared.adbConnecting = false
                        }
                        clearConnectionFlag()
                    }
                    return
                }
                
                logBinaryDetection("Using ADB ports from device: \(devicePorts.joined(separator: ", "))")
                let portsToTry = devicePorts.compactMap { UInt16($0) }
                
                guard !portsToTry.isEmpty else {
                    DispatchQueue.main.async {
                        AppState.shared.adbConnectionResult = "Device reported ADB ports but none could be parsed as valid port numbers."
                        AppState.shared.adbConnected = false
                        AppState.shared.adbConnecting = false
                    }
                    clearConnectionFlag()
                    return
                }
                
                proceedWithConnection(adbPath: adbPath, ip: ip, portsToTry: portsToTry)
            }
        }
    }

    private static func connectedWirelessPort(adbPath: String, ip: String) -> UInt16? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["devices"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            for line in (String(data: data, encoding: .utf8) ?? "").split(separator: "\n") {
                let fields = line.split(whereSeparator: { $0.isWhitespace })
                guard fields.count >= 2, fields[1] == "device",
                      fields[0].hasPrefix(ip + ":"),
                      let port = UInt16(fields[0].dropFirst(ip.count + 1)), port > 0 else { continue }
                return port
            }
        } catch { print("[adb-connector] Could not inspect active transports: \(error)") }
        return nil
    }

    private static func discoverADBPorts(adbPath: String, ip: String, completion: @escaping ([UInt16]) -> Void) {
        runADBCommand(adbPath: adbPath, arguments: ["mdns", "services"], completion: { output in
            let lines = output.components(separatedBy: .newlines)
            var ports: [UInt16] = []
            
            for line in lines {
                if line.contains(ip) {
                    let parts = line.split(separator: ":")
                    if parts.count >= 2 {
                        let portPart = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let numericPort = portPart.filter { "0123456789".contains($0) }
                        if let port = UInt16(numericPort) {
                            if !ports.contains(port) {
                                ports.append(port)
                            }
                        }
                    }
                }
            }
            completion(ports)
        })
    }

    private static func proceedWithConnection(adbPath: String, ip: String, portsToTry: [UInt16]) {
        logBinaryDetection("Proceeding with ADB connection attempts to \(ip)...")

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
            attemptConnectionToNextPort(adbPath: adbPath, ip: ip, portsToTry: portsToTry, currentIndex: 0, reportedIP: ip)
        }
    }

    private static let adbFailureSuggestions: [String] = [
        "Pair your device using either the \"Pair with ADB QR\" button or via the command line (adb pair)",
        "Ensure your Android device has Wireless Debugging enabled",
        "Reconnect to the exact same Wi-Fi network as your Mac"
    ]

    private static let adbFailureReasonsByOutput: [(match: String, reason: String)] = [
        ("failed to authenticate", "Your Mac isn't authorized to debug this device yet — it needs to be paired again."),
        ("unauthorized", "Your Mac isn't authorized to debug this device yet — it needs to be paired again."),
        ("connection refused", "The device refused the connection. This usually means it hasn't been paired with this Mac (via \"adb pair\") since Wireless Debugging was last turned on."),
        ("no route to host", "Your Mac can't reach the device on the network — check they're both on the same Wi-Fi."),
        ("network is unreachable", "Your Mac can't reach the device on the network — check they're both on the same Wi-Fi."),
        ("timed out", "The connection attempt timed out — check that both devices are on the same Wi-Fi network and Wireless Debugging is still on.")
    ]

    private static func diagnosis(for outputs: [String]) -> String? {
        for output in outputs {
            for entry in adbFailureReasonsByOutput where output.contains(entry.match) {
                return entry.reason
            }
        }
        return nil
    }

    private static func buildADBFailureAlertText(failureOutputs: [String]) -> String {
        var sections: [String] = []

        if let diagnosis = diagnosis(for: failureOutputs) {
            sections.append("What happened:\n\(diagnosis)")
        }

        let suggestionsList = adbFailureSuggestions.map { "• \($0)" }.joined(separator: "\n")
        sections.append("Suggestions:\n\(suggestionsList)")

        return sections.joined(separator: "\n\n")
    }

    private static func attemptConnectionToNextPort(adbPath: String, ip: String, portsToTry: [UInt16], currentIndex: Int, reportedIP: String? = nil, failureOutputs: [String] = []) {
        if currentIndex >= portsToTry.count {
            if let reportedIP = reportedIP, reportedIP != ip {
                logBinaryDetection("Failed to connect on discovered IP \(ip), attempting fallback to reported IP \(reportedIP)...")
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
                    attemptConnectionToNextPort(adbPath: adbPath, ip: reportedIP, portsToTry: portsToTry, currentIndex: 0, reportedIP: nil, failureOutputs: failureOutputs)
                }
                return
            }

            DispatchQueue.main.async {
                AppState.shared.adbConnected = false
                logBinaryDetection("(∩︵∩) ADB connection failed on all ports.")
                let rawOutputSummary = failureOutputs.isEmpty ? "Failed to connect to device on any available port." : failureOutputs.joined(separator: "\n")
                AppState.shared.adbConnectionResult = (AppState.shared.adbConnectionResult ?? "") + "\n" + rawOutputSummary
                AppState.shared.adbConnecting = false

                if !AppState.shared.suppressAdbFailureAlerts {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Pair with ADB QR")
                    alert.addButton(withTitle: "Don't warn me again")
                    alert.messageText = "Failed to connect to ADB."
                    alert.informativeText = buildADBFailureAlertText(failureOutputs: failureOutputs)

                    presentAlertAsynchronously(alert) { response in
                        if response == .alertSecondButtonReturn {
                            AppState.shared.showADBPairingSheet = true
                        } else if response == .alertThirdButtonReturn {
                            AppState.shared.suppressAdbFailureAlerts = true
                        }
                    }
                }
            }
            clearConnectionFlag()
            return
        }

        let currentPort = portsToTry[currentIndex]
        let fullAddress = "\(ip):\(currentPort)"
        logBinaryDetection("Attempting connection to port \(currentPort) (attempt \(currentIndex + 1)/\(portsToTry.count)): \(fullAddress)")

        runADBCommand(adbPath: adbPath, arguments: ["connect", fullAddress], completion: { output in
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            DispatchQueue.main.async {
                UserDefaults.standard.lastADBCommand = "adb connect \(fullAddress)"

                if trimmedOutput.contains("connected to") {
                    AppState.shared.adbConnected = true
                    AppState.shared.adbPort = currentPort
                    AppState.shared.adbConnectedIP = ip
                    AppState.shared.adbConnectionResult = trimmedOutput
                    logBinaryDetection("(/^▽^)/ ADB connection successful to \(fullAddress)")
                    AppState.shared.adbConnecting = false
                    clearConnectionFlag()
                } else {
                    logBinaryDetection("Port \(currentPort) failed, trying next...")
                    let updatedFailureOutputs = failureOutputs + ["\(fullAddress): \(trimmedOutput)"]
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
                        attemptConnectionToNextPort(adbPath: adbPath, ip: ip, portsToTry: portsToTry, currentIndex: currentIndex + 1, reportedIP: reportedIP, failureOutputs: updatedFailureOutputs)
                    }
                }
            }
        })
    }

    static func disconnectADB() {
        let adbIP = AppState.shared.adbConnectedIP
        let adbPort = AppState.shared.adbPort
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else {
                DispatchQueue.main.async {
                    AppState.shared.adbConnected = false
                }
                return
            }

            if !adbIP.isEmpty {
                let fullAddress = "\(adbIP):\(adbPort)"
                runADBCommand(adbPath: adbPath, arguments: ["disconnect", fullAddress])
            }
            
            DispatchQueue.main.async {
                AppState.shared.adbConnected = false
                AppState.shared.adbConnecting = false
            }
        }
    }

    private static func runADBCommand(
        adbPath: String,
        arguments: [String],
        onOutput: ((String) -> Void)? = nil,
        completion: ((String) -> Void)? = nil
    ) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: adbPath)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        var fullOutput = ""
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let str = String(data: data, encoding: .utf8) {
                fullOutput += str
                onOutput?(str)
                
                if !arguments.contains("mdns") && !arguments.contains("kill-server") {
                    DispatchQueue.main.async {
                        AppState.shared.adbConnectionResult = (AppState.shared.adbConnectionResult ?? "") + str
                    }
                }
            }
        }

        task.terminationHandler = { _ in
            completion?(fullOutput)
        }

        do {
            try task.run()
        } catch {
            completion?("Failed to run \(adbPath): \(error.localizedDescription)")
        }
    }

    static func startScrcpy(
        ip: String,
        port: UInt16,
        deviceName: String,
        desktop: Bool? = false,
        package: String? = nil
    ) {
        let bitrate = AppState.shared.scrcpyBitrate
        let resolution = AppState.shared.scrcpyResolution
        let wiredAdbEnabled = AppState.shared.wiredAdbEnabled
        let alwaysOnTop = UserDefaults.standard.scrcpyOnTop
        let stayAwake = UserDefaults.standard.stayAwake
        let turnScreenOff = UserDefaults.standard.turnScreenOff
        let noAudio = UserDefaults.standard.noAudio
        let keepPhoneAudio = UserDefaults.standard.object(forKey: "keepPhoneAudio") as? Bool ?? true
        let audioBufferMS = Int(min(500, max(60, UserDefaults.standard.object(forKey: "phoneAudioBufferMS") as? Double ?? 200)))
        let manualPosition = UserDefaults.standard.manualPosition
        let manualPositionCoords = UserDefaults.standard.manualPositionCoords
        let continueApp = UserDefaults.standard.continueApp
        let directKeyInput = UserDefaults.standard.directKeyInput
        let followMacKeyboard = UserDefaults.standard.object(forKey: "followMacKeyboardLayout") as? Bool ?? true
        let dpi = UserDefaults.standard.scrcpyDesktopDpi

        DispatchQueue.global(qos: .userInitiated).async {
            guard let scrcpyPath = findExecutable(named: "scrcpy", fallbackPaths: possibleScrcpyPaths) else {
                DispatchQueue.main.async {
                    AppState.shared.adbConnectionResult = "scrcpy not found."
                    presentScrcpyAlert(title: "scrcpy Not Found", informative: "AirSync couldn't find the scrcpy binary.")
                }
                return
            }

            let fullAddress = "\(ip):\(port)"
            let deviceNameFormatted = deviceName.removingApostrophesAndPossessives()
            
            var args = [
                "--window-title=\(deviceNameFormatted)",
                "--video-bit-rate=\(bitrate)M",
                "--video-codec=h265",
                "--no-power-on"
            ]

            let mappedSerial = AppState.shared.selectedWiredSerial ?? (AppState.shared.device?.deviceId).flatMap { AppState.shared.deviceAdbSerials[$0] }
            
            getWiredDevices { devices in
                let serialToUse: String?
                if let mapped = mappedSerial, devices.contains(where: { $0.serial == mapped }) {
                    serialToUse = mapped
                } else {
                    serialToUse = devices.first?.serial
                }
                
                DispatchQueue.global(qos: .userInitiated).async {
                    if wiredAdbEnabled, let serial = serialToUse {
                        args.append("--serial=\(serial)")
                        DispatchQueue.main.async { AppState.shared.adbConnectionMode = .wired }
                        logBinaryDetection("Wired ADB prioritized: using serial \(serial)")
                    } else {
                        args.append("--tcpip=\(fullAddress)")
                        DispatchQueue.main.async { AppState.shared.adbConnectionMode = .wireless }
                    }

                    if manualPosition {
                        args.append("--window-x=\(manualPositionCoords[0])")
                        args.append("--window-y=\(manualPositionCoords[1])")
                    }
                    if alwaysOnTop { args.append("--always-on-top") }
                    if stayAwake { args.append(contentsOf: ["--stay-awake", "--keep-active"]) }
                    if turnScreenOff { args.append("--turn-screen-off") }
                    if noAudio { args.append("--no-audio") }
                    else {
                        args.append("--audio-source=playback")
                        args.append("--audio-buffer=\(audioBufferMS)")
                        if keepPhoneAudio { args.append("--audio-dup") }
                    }
                    if followMacKeyboard || directKeyInput { args.append("--keyboard=uhid") }

                    let displayArg = "/\(dpi)"

                    if desktop ?? true {
                        args.append("--new-display=\(displayArg)")
                        args.append("-x")
                    } else if package == nil {
                        // Only add max-size for regular mirror
                        args.append("--max-size=\(resolution)")
                    }

                    if let pkg = package {
                        args.append(contentsOf: ["--new-display=\(displayArg)", "--start-app=\(pkg)", "--no-vd-system-decorations", "-x"])
                        if continueApp { args.append("--no-vd-destroy-content") }
                    }

                    logBinaryDetection("Launching scrcpy: \(scrcpyPath) \(args.joined(separator: " "))")
                    var environment = ProcessInfo.processInfo.environment
                    if let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) {
                        let adbDir = URL(fileURLWithPath: adbPath).deletingLastPathComponent().path
                        environment["PATH"] = "\(adbDir):" + (environment["PATH"] ?? "")
                        environment["ADB"] = adbPath
                    }
                    do {
                        let serial = wiredAdbEnabled ? (serialToUse ?? fullAddress) : fullAddress
                        try launchMirrorWindow(executable: scrcpyPath, arguments: args, environment: environment,
                                               serial: serial, followKeyboard: followMacKeyboard)
                        if package == nil {
                            DispatchQueue.main.async {
                                AppState.shared.rememberMirrorMode(desktop == true ? .scrcpyDesktop : .scrcpy)
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            AppState.shared.adbConnectionResult = "Failed to start scrcpy: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    static func pull(remotePath: String, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.begin { response in
                if response == .OK, let destinationURL = panel.url {
                    let fileName = (remotePath as NSString).lastPathComponent
                    let destiny = destinationURL.appendingPathComponent(fileName).path
                    
                    let wiredAdbEnabled = AppState.shared.wiredAdbEnabled
                    let fullAddress = "\(AppState.shared.adbConnectedIP):\(AppState.shared.adbPort)"
                    AppState.shared.isADBTransferring = true
                    AppState.shared.adbTransferringFilePath = remotePath

                    let mappedSerial = AppState.shared.selectedWiredSerial ?? (AppState.shared.device?.deviceId).flatMap { AppState.shared.deviceAdbSerials[$0] }
                    
                    getWiredDevices { devices in
                        let serialToUse: String?
                        if let mapped = mappedSerial, devices.contains(where: { $0.serial == mapped }) {
                            serialToUse = mapped
                        } else {
                            serialToUse = devices.first?.serial
                        }
                        
                        DispatchQueue.global(qos: .userInitiated).async {
                            guard let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else {
                                DispatchQueue.main.async { AppState.shared.isADBTransferring = false }
                                completion?(false)
                                return
                            }
                            
                            var args = ["pull", remotePath, destiny]
                            if wiredAdbEnabled, let serial = serialToUse {
                                args.insert(contentsOf: ["-s", serial], at: 0)
                            } else {
                                args.insert(contentsOf: ["-s", fullAddress], at: 0)
                            }
                            
                            runADBCommand(adbPath: adbPath, arguments: args) { output in
                                let success = !output.contains("error") && !output.contains("failed")
                                DispatchQueue.main.async {
                                    AppState.shared.isADBTransferring = false
                                    AppState.shared.adbTransferringFilePath = nil
                                    if success { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: destiny) }
                                    completion?(success)
                                }
                            }
                        }
                    }
                } else {
                    completion?(false)
                }
            }
        }
    }

    static func summonScreenshot(completion: @escaping (Data?) -> Void) {
        let wiredAdbEnabled = AppState.shared.wiredAdbEnabled
        let fullAddress = "\(AppState.shared.adbConnectedIP):\(AppState.shared.adbPort)"
        let mappedSerial = AppState.shared.selectedWiredSerial ?? (AppState.shared.device?.deviceId).flatMap { AppState.shared.deviceAdbSerials[$0] }

        getWiredDevices { devices in
            let serialToUse: String?
            if let mapped = mappedSerial, devices.contains(where: { $0.serial == mapped }) {
                serialToUse = mapped
            } else {
                serialToUse = devices.first?.serial
            }

            DispatchQueue.global(qos: .userInitiated).async {
                guard let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else {
                    completion(nil)
                    return
                }

                var args = ["exec-out", "screencap", "-p"]
                if wiredAdbEnabled, let serial = serialToUse {
                    args.insert(contentsOf: ["-s", serial], at: 0)
                } else {
                    args.insert(contentsOf: ["-s", fullAddress], at: 0)
                }

                let task = Process()
                task.executableURL = URL(fileURLWithPath: adbPath)
                task.arguments = args

                let outPipe = Pipe()
                task.standardOutput = outPipe
                task.standardError = Pipe() // discard stderr so it doesn't mix into the PNG stream

                do {
                    try task.run()
                } catch {
                    logBinaryDetection("Summon screenshot failed to launch adb: \(error.localizedDescription)")
                    completion(nil)
                    return
                }

                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()

                // A valid PNG starts with this 8-byte signature; adb error text wouldn't.
                let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
                guard data.count > pngSignature.count, Array(data.prefix(pngSignature.count)) == pngSignature else {
                    logBinaryDetection("Summon screenshot did not return valid PNG data (\(data.count) bytes)")
                    completion(nil)
                    return
                }

                completion(data)
            }
        }
    }

    static func push(localPath: String, remotePath: String, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.main.async {
            let wiredAdbEnabled = AppState.shared.wiredAdbEnabled
            let fullAddress = "\(AppState.shared.adbConnectedIP):\(AppState.shared.adbPort)"
            AppState.shared.isADBTransferring = true
            AppState.shared.adbTransferringFilePath = remotePath

            let mappedSerial = AppState.shared.selectedWiredSerial ?? (AppState.shared.device?.deviceId).flatMap { AppState.shared.deviceAdbSerials[$0] }
            
            getWiredDevices { devices in
                let serialToUse: String?
                if let mapped = mappedSerial, devices.contains(where: { $0.serial == mapped }) {
                    serialToUse = mapped
                } else {
                    serialToUse = devices.first?.serial
                }
                
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else {
                        DispatchQueue.main.async { AppState.shared.isADBTransferring = false }
                        completion?(false)
                        return
                    }

                    var args = ["push", localPath, remotePath]
                    if wiredAdbEnabled, let serial = serialToUse {
                        args.insert(contentsOf: ["-s", serial], at: 0)
                    } else {
                        args.insert(contentsOf: ["-s", fullAddress], at: 0)
                    }
                    
                    runADBCommand(adbPath: adbPath, arguments: args) { output in
                        let success = !output.contains("error") && !output.contains("failed")
                        DispatchQueue.main.async {
                            AppState.shared.isADBTransferring = false
                            AppState.shared.adbTransferringFilePath = nil
                            completion?(success)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Alert Helper
private extension ADBConnector {
    static func presentAlertAsynchronously(_ alert: NSAlert, completion: ((NSApplication.ModalResponse) -> Void)? = nil) {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { $0.isKeyWindow && $0.isVisible }) ?? NSApp.windows.first(where: { $0.isVisible }) {
                alert.beginSheetModal(for: window) { response in
                    completion?(response)
                }
            } else {
                NSApp.activate(ignoringOtherApps: true)
                let response = alert.runModal()
                completion?(response)
            }
        }
    }

    static func presentScrcpyAlert(title: String, informative: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = informative + "\n\nCheck the ADB Console in Settings for detailed logs."
        alert.addButton(withTitle: "OK")
        presentAlertAsynchronously(alert)
    }

    static func presentScrcpyPairingAlert(title: String, informative: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = informative + "\n\nCheck the ADB Console in Settings for detailed logs."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Pair with ADB QR")
        
        presentAlertAsynchronously(alert) { response in
            if response == .alertSecondButtonReturn {
                AppState.shared.showADBPairingSheet = true
            }
        }
    }
}
