import AppKit
import Carbon

/// Matches scrcpy's virtual physical keyboard to the active Mac input source.
/// The Android helper touches only keyboards created by scrcpy, not the phone IME.
final class KeyboardLayoutSync {
    static let shared = KeyboardLayoutSync()

    private struct Session {
        let process: Process
        let adbPath: String
        let serial: String
        var revision = 0
    }

    private var sessions: [Int32: Session] = [:]
    private let worker = DispatchQueue(label: "com.airsync.keyboard-layout")
    private var uploadedSerials = Set<String>() // accessed only by worker
    private var observer: NSObjectProtocol?

    private init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshAll() }
    }

    func register(process: Process, adbPath: String, serial: String) {
        guard process.isRunning else { return }
        sessions[process.processIdentifier] = Session(process: process, adbPath: adbPath, serial: serial)
        refresh(process.processIdentifier)
    }

    func remove(processID: Int32) { sessions.removeValue(forKey: processID) }

    private func refreshAll() {
        for id in Array(sessions.keys) { refresh(id) }
    }

    private func refresh(_ id: Int32) {
        guard var session = sessions[id], session.process.isRunning else {
            sessions.removeValue(forKey: id)
            return
        }
        session.revision += 1
        sessions[id] = session
        synchronize(id, revision: session.revision, attempt: 0)
    }

    private func synchronize(_ id: Int32, revision: Int, attempt: Int) {
        guard let session = sessions[id], session.revision == revision, session.process.isRunning,
              let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let languagesPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
              let resource = Bundle.main.path(forResource: "KeyboardLayoutBridge", ofType: "jar") else { return }
        let languages = Unmanaged<CFArray>.fromOpaque(languagesPointer).takeUnretainedValue() as! [String]
        guard let language = languages.first else { return }
        let sourceID: String
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            sourceID = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        } else { sourceID = "" }
        let variant = sourceID.lowercased().contains("russian") && !sourceID.lowercased().contains("win") ? "mac" : "pc"
        let locale = language.replacingOccurrences(of: "_", with: "-")
        worker.async { [weak self] in
            guard let self else { return }
            let remote = "/data/local/tmp/airsync-keyboard-layout.jar"
            if !self.uploadedSerials.contains(session.serial) {
                let push = self.runADB(session, ["push", resource, remote])
                guard push.1 == 0 else {
                    print("[keyboard-layout] Helper upload failed: \(push.0)")
                    return
                }
                self.uploadedSerials.insert(session.serial)
            }
            let result = self.runADB(session, ["shell", "CLASSPATH=\(remote)", "app_process", "/",
                                               "com.airsync.KeyboardLayoutBridge", locale, variant])
            DispatchQueue.main.async { [weak self] in
                guard let self, self.sessions[id]?.revision == revision else { return }
                if result.1 == 3 && attempt < 12 {
                    // UHID becomes available shortly after the scrcpy server starts.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.synchronize(id, revision: revision, attempt: attempt + 1)
                    }
                } else {
                    print("[keyboard-layout] \(result.0.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
    }

    private func runADB(_ session: Session, _ arguments: [String]) -> (String, Int32) {
        guard session.process.isRunning else { return ("Mirror closed", -1) }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: session.adbPath)
        task.arguments = ["-s", session.serial] + arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                if task.isRunning { task.terminate() }
            }
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return (String(data: output, encoding: .utf8) ?? "", task.terminationStatus)
        } catch { return (error.localizedDescription, -1) }
    }
}
