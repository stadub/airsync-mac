import Foundation

/// scrcpy raw audio is interleaved 48 kHz stereo signed 16-bit little-endian PCM.
enum ScrcpyPCM {
    static func decode(_ data: Data) -> (left: [Float], right: [Float])? {
        guard !data.isEmpty, data.count % 4 == 0 else { return nil }
        let bytes = [UInt8](data)
        var left = [Float](), right = [Float]()
        left.reserveCapacity(bytes.count / 4)
        right.reserveCapacity(bytes.count / 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let l = Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
            let r = Int16(bitPattern: UInt16(bytes[index + 2]) | UInt16(bytes[index + 3]) << 8)
            left.append(Float(l) / 32768)
            right.append(Float(r) / 32768)
        }
        return (left, right)
    }
}
