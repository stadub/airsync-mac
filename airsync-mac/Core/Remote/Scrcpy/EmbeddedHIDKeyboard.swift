import Foundation

/// Boot-keyboard reports carried by scrcpy's UHID control messages (v4.1).
struct EmbeddedHIDKeyboard {
    private var pressed = Set<UInt8>()
    private static let id: UInt16 = 1
    private static let descriptor: [UInt8] = [
        0x05,0x01,0x09,0x06,0xA1,0x01,0x05,0x07,0x19,0xE0,0x29,0xE7,
        0x15,0x00,0x25,0x01,0x75,0x01,0x95,0x08,0x81,0x02,
        0x95,0x01,0x75,0x08,0x81,0x01,
        0x95,0x05,0x75,0x01,0x05,0x08,0x19,0x01,0x29,0x05,0x91,0x02,
        0x95,0x01,0x75,0x03,0x91,0x01,
        0x95,0x06,0x75,0x08,0x15,0x00,0x25,0x65,0x05,0x07,0x19,0x00,0x29,0x65,0x81,0x00,0xC0
    ]
    private static let usages: [UInt16: UInt8] = [
        0:4, 11:5, 8:6, 2:7, 14:8, 3:9, 5:10, 4:11, 34:12, 38:13,
        40:14, 37:15, 46:16, 45:17, 31:18, 35:19, 12:20, 15:21, 1:22,
        17:23, 32:24, 9:25, 13:26, 7:27, 16:28, 6:29,
        18:30, 19:31, 20:32, 21:33, 23:34, 22:35, 26:36, 28:37, 25:38, 29:39,
        36:40, 53:41, 51:42, 48:43, 49:44, 27:45, 24:46, 33:47, 30:48,
        42:49, 41:51, 39:52, 50:53, 43:54, 47:55, 44:56, 57:57,
        122:58, 120:59, 99:60, 118:61, 96:62, 97:63, 98:64, 100:65,
        101:66, 109:67, 103:68, 111:69,
        114:73, 115:74, 116:75, 117:76, 119:77, 121:78,
        124:79, 123:80, 125:81, 126:82, 71:83, 75:84, 67:85, 78:86, 69:87,
        76:88, 83:89, 84:90, 85:91, 86:92, 87:93, 88:94, 89:95, 91:96,
        92:97, 82:98, 65:99, 10:100, 81:103
    ]

    static func createMessage() -> Data {
        let name = Array("scrcpy AirSync".utf8)
        var data = Data([12])
        append16(id, to: &data)
        append16(0, to: &data) // vendor
        append16(0, to: &data) // product
        data.append(UInt8(name.count))
        data.append(contentsOf: name)
        append16(UInt16(descriptor.count), to: &data)
        data.append(contentsOf: descriptor)
        return data
    }

    mutating func key(macKeycode: UInt16, down: Bool, modifiers: UInt8) -> Data? {
        guard let usage = Self.usages[macKeycode], usage <= 101 else { return nil }
        if down { pressed.insert(usage) } else { pressed.remove(usage) }
        return report(modifiers: modifiers)
    }

    func report(modifiers: UInt8) -> Data {
        let keys = pressed.count > 6 ? [UInt8](repeating: 1, count: 6) : pressed.sorted()
        var bytes: [UInt8] = [modifiers, 0] + keys
        bytes += [UInt8](repeating: 0, count: 8 - bytes.count)
        var message = Data([13])
        Self.append16(Self.id, to: &message)
        Self.append16(UInt16(bytes.count), to: &message)
        message.append(contentsOf: bytes)
        return message
    }

    mutating func releaseAll() -> Data {
        pressed.removeAll()
        return report(modifiers: 0)
    }

    private static func append16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value >> 8))
        data.append(UInt8(value & 0xff))
    }
}
