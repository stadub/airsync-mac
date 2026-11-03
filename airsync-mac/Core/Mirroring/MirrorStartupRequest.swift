import Foundation

/// Cancellation and completion ownership for one asynchronous native startup.
nonisolated final class MirrorStartupRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var completion: ((Bool, String?) -> Void)?

    init(completion: @escaping (Bool, String?) -> Void) { self.completion = completion }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func finish(_ success: Bool, error: String? = nil) {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(success, error)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(false, "Mirroring startup cancelled.")
    }
}
