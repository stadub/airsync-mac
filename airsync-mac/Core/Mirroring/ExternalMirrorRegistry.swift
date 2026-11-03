import Foundation
import Darwin

nonisolated struct MirrorLaunchConfiguration: Sendable {
    let executable: String
    var arguments: [String]
    let environment: [String: String]?
    let serial: String
    let followKeyboard: Bool

    var isScreenMirror: Bool {
        !arguments.contains { $0.hasPrefix("--new-display") || $0.hasPrefix("--start-app=") }
    }
}

nonisolated protocol MirrorManagedProcess: AnyObject, Sendable {
    var identifier: Int32 { get }
    var foundationProcess: Process? { get }
    var isRunning: Bool { get }
    func start(onExit: @escaping (Int32, String) -> Void) throws
    func stop()
}

nonisolated final class FoundationMirrorProcess: MirrorManagedProcess, @unchecked Sendable {
    private let process = Process()
    private let output = ProcessOutputCapture()
    var identifier: Int32 { process.processIdentifier }
    var foundationProcess: Process? { process }
    var isRunning: Bool { process.isRunning }

    init(configuration: MirrorLaunchConfiguration) {
        process.executableURL = URL(fileURLWithPath: configuration.executable)
        process.arguments = configuration.arguments
        process.environment = configuration.environment
        process.standardOutput = output.pipe
        process.standardError = output.pipe
    }

    func start(onExit: @escaping (Int32, String) -> Void) throws {
        output.start()
        process.terminationHandler = { [output] process in
            onExit(process.terminationStatus, output.finish())
        }
        do { try process.run() }
        catch { _ = output.finish(); throw error }
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        let process = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
    }
}

/// Owns external mirror lifetime; UI and discovery are supplied at the boundary.
nonisolated final class ExternalMirrorRegistry: @unchecked Sendable {
    typealias Factory = (MirrorLaunchConfiguration) -> MirrorManagedProcess
    private struct Entry {
        let id: UUID
        let configuration: MirrorLaunchConfiguration
        let process: MirrorManagedProcess
    }

    private let queue = DispatchQueue(label: "com.airsync.external-mirrors")
    private let intentLock = NSLock()
    private var desired: [UUID: Bool] = [:] // true denotes a full-phone mirror
    private var entries: [UUID: Entry] = [:] // accessed only on queue
    private var stopping = Set<Int32>()
    private var processes: [Int32: MirrorManagedProcess] = [:]
    private let factory: Factory
    private let onStarted: (MirrorLaunchConfiguration, MirrorManagedProcess) -> Void
    private let onExited: (Int32, Int32, String, Bool) -> Void
    private let onScreenCountChanged: (Int) -> Void

    init(factory: @escaping Factory = { FoundationMirrorProcess(configuration: $0) },
         onStarted: @escaping (MirrorLaunchConfiguration, MirrorManagedProcess) -> Void = { _, _ in },
         onExited: @escaping (Int32, Int32, String, Bool) -> Void = { _, _, _, _ in },
         onScreenCountChanged: @escaping (Int) -> Void = { _ in }) {
        self.factory = factory
        self.onStarted = onStarted
        self.onExited = onExited
        self.onScreenCountChanged = onScreenCountChanged
    }

    private func isDesired(_ id: UUID) -> Bool {
        intentLock.lock()
        defer { intentLock.unlock() }
        return desired[id] != nil
    }

    private func removeIntent(_ id: UUID) {
        intentLock.lock()
        desired.removeValue(forKey: id)
        intentLock.unlock()
    }

    func launch(_ configuration: MirrorLaunchConfiguration, completion: @escaping (String?) -> Void) {
        let id = UUID()
        intentLock.lock()
        desired[id] = configuration.isScreenMirror
        intentLock.unlock()
        queue.async {
            do {
                try self.start(id: id, configuration: configuration)
                completion(nil)
            } catch {
                self.removeIntent(id)
                completion(error.localizedDescription)
            }
        }
    }

    private func start(id: UUID, configuration: MirrorLaunchConfiguration) throws {
        guard isDesired(id) else { return }
        let process = factory(configuration)
        try process.start { [weak self, weak process] status, output in
            guard let self, let process else { return }
            self.queue.async {
                let pid = process.identifier
                let intentional = self.stopping.remove(pid) != nil
                if self.entries[id]?.process.identifier == pid {
                    self.entries.removeValue(forKey: id)
                    self.removeIntent(id)
                }
                self.processes.removeValue(forKey: pid)
                self.publishCount()
                self.onExited(pid, status, output, intentional)
            }
        }
        processes[process.identifier] = process
        guard isDesired(id) else {
            stopping.insert(process.identifier)
            process.stop()
            return
        }
        entries[id] = Entry(id: id, configuration: configuration, process: process)
        publishCount()
        onStarted(configuration, process)
    }

    func closeScreenMirrors(completion: @escaping () -> Void) {
        // Cancel desired state immediately, even if restart is currently stopping
        // a process on the serial queue. That restart cannot recreate this window.
        intentLock.lock()
        desired = desired.filter { !$0.value }
        intentLock.unlock()
        queue.async {
            for entry in Array(self.entries.values) where entry.configuration.isScreenMirror {
                self.entries.removeValue(forKey: entry.id)
                self.stopping.insert(entry.process.identifier)
                entry.process.stop()
            }
            self.publishCount()
            completion()
        }
    }

    func restartAudio(_ options: MirrorAudioOptions, completion: @escaping (String?) -> Void) {
        queue.async {
            var errors: [String] = []
            for entry in Array(self.entries.values) {
                self.entries.removeValue(forKey: entry.id)
                self.stopping.insert(entry.process.identifier)
                entry.process.stop()
                guard self.isDesired(entry.id) else { continue }
                var replacement = entry.configuration
                replacement.arguments = options.applying(to: replacement.arguments)
                do { try self.start(id: entry.id, configuration: replacement) }
                catch { self.removeIntent(entry.id); errors.append(error.localizedDescription) }
            }
            self.publishCount()
            completion(errors.isEmpty ? nil : errors.joined(separator: "\n"))
        }
    }

    private func publishCount() {
        onScreenCountChanged(entries.values.filter { $0.configuration.isScreenMirror && $0.process.isRunning }.count)
    }
}
