import Foundation

/// Everything the app needs to know about the recorder's BLE protocol.
///
/// The real values for the Boya Notra NEO are NOT public. Fill them in from your
/// reverse-engineering session (see docs/REVERSE_ENGINEERING.md) — either by
/// editing `DeviceProfile.notraNeoDraft` below or by pasting JSON in
/// Ajustes → Perfil BLE inside the app, no rebuild needed.
struct DeviceProfile: Codable, Equatable {
    enum AudioFormat: String, Codable, CaseIterable {
        /// The device streams a complete file (WAV/MP3/OPUS container); save bytes as-is.
        case rawFile
        /// Headerless signed 16-bit little-endian PCM; we wrap it in a WAV header.
        case pcm16
        /// Opus or ADPCM frames — needs a decoder (TODO once the framing is known).
        case opus
        case imaAdpcm
    }

    var name: String
    /// Advertised name prefixes used to pick the recorder out of the scan list.
    var namePrefixes: [String]
    /// Primary service UUID (nil = scan everything and let the user pick).
    var serviceUUID: String?
    /// Characteristic the app writes commands to.
    var writeUUID: String?
    /// Characteristic the device sends data back on (notify/indicate).
    var notifyUUID: String?
    /// Use write-with-response (true) or write-without-response (false).
    var writeWithResponse: Bool

    /// Hex command that asks for the list of recordings (optional).
    var listCommandHex: String?
    /// Hex template to download recording N. Placeholders:
    ///   {idx16le} {idx32le} {idx16be} {idx32be} — recording index
    var downloadCommandHex: String?
    /// Hex sent after each received chunk if the device needs ACKs (optional).
    var ackCommandHex: String?
    /// Hex prefix that marks the end of a transfer (optional; else idle timeout).
    var endOfTransferHex: String?
    /// Bytes to strip from the start of every notification (packet header / seq no.)
    var headerBytesPerPacket: Int
    /// Seconds without packets after which a transfer is considered done.
    var idleTimeout: Double

    var audioFormat: AudioFormat
    var fileExtension: String
    var sampleRate: Int
    var channels: Int

    /// Placeholder profile. Every `nil`/guess here must be confirmed by capture.
    static let notraNeoDraft = DeviceProfile(
        name: "Boya Notra NEO (borrador)",
        namePrefixes: ["NOTRA", "Notra", "BOYA", "BY-"],
        serviceUUID: nil,
        writeUUID: nil,
        notifyUUID: nil,
        writeWithResponse: false,
        listCommandHex: nil,
        downloadCommandHex: nil,
        ackCommandHex: nil,
        endOfTransferHex: nil,
        headerBytesPerPacket: 0,
        idleTimeout: 3,
        audioFormat: .rawFile,
        fileExtension: "wav",
        sampleRate: 16000,
        channels: 1)
}

extension DeviceProfile {
    private static let key = "deviceProfile.json"

    static func load() -> DeviceProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              let p = try? JSONDecoder().decode(DeviceProfile.self, from: data) else {
            return .notraNeoDraft
        }
        return p
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    var prettyJSON: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// CBUUID(string:) raises an ObjC exception on malformed input, so validate first.
    static func isValidUUID(_ s: String) -> Bool {
        s.range(of: "^([0-9A-Fa-f]{4}|[0-9A-Fa-f]{8}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})$",
                options: .regularExpression) != nil
    }

    func downloadCommand(index: Int) -> Data? {
        guard var t = downloadCommandHex else { return nil }
        let i = UInt32(truncatingIfNeeded: index)
        func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
        t = t.replacingOccurrences(of: "{idx16le}", with: hex([UInt8(i & 0xff), UInt8((i >> 8) & 0xff)]))
        t = t.replacingOccurrences(of: "{idx16be}", with: hex([UInt8((i >> 8) & 0xff), UInt8(i & 0xff)]))
        t = t.replacingOccurrences(of: "{idx32le}", with: hex((0..<4).map { UInt8((i >> ($0 * 8)) & 0xff) }))
        t = t.replacingOccurrences(of: "{idx32be}", with: hex((0..<4).reversed().map { UInt8((i >> ($0 * 8)) & 0xff) }))
        return Data(hexString: t)
    }
}

extension Data {
    init?(hexString: String) {
        let clean = hexString.filter { $0.isHexDigit }
        guard clean.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard let b = UInt8(clean[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        self.init(bytes)
    }

    var hexString: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}
