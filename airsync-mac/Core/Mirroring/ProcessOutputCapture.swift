import Foundation
import Darwin

/// Continuously drain both process streams while retaining only a bounded tail.
nonisolated final class ProcessOutputCapture {
    let pipe = Pipe()
    private let queue = DispatchQueue(label: "com.airsync.process-output")
    private var source: DispatchSourceRead?
    private var tail = Data()
    private let capacity: Int

    init(capacity: Int = 65_536) { self.capacity = max(1, capacity) }

    func start() {
        let fd = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        self.source = source
        source.resume()
    }

    private func drain() {
        let fd = pipe.fileHandleForReading.fileDescriptor
        var bytes = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count > 0 {
                tail.append(contentsOf: bytes.prefix(count))
                if tail.count > capacity { tail.removeFirst(tail.count - capacity) }
            } else if count == 0 { source?.cancel(); return }
            else if count < 0 && errno == EINTR { continue }
            else { return }
        }
    }

    func finish() -> String {
        queue.sync {
            drain()
            source?.cancel()
            source = nil
            return String(decoding: tail, as: UTF8.self)
        }
    }
}
