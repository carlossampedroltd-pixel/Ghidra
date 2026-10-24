import Foundation

/// Turns the raw bytes received from the recorder into an audio file on disk.
enum AudioPacker {
    static func makeFile(from data: Data, profile: DeviceProfile) throws -> URL {
        let name = "notra-\(Int(Date().timeIntervalSince1970))"
        let tmp = FileManager.default.temporaryDirectory
        switch profile.audioFormat {
        case .rawFile:
            let url = tmp.appendingPathComponent("\(name).\(sniffExtension(data) ?? profile.fileExtension)")
            try data.write(to: url)
            return url
        case .pcm16:
            let url = tmp.appendingPathComponent("\(name).wav")
            try wav(pcm16: data, sampleRate: profile.sampleRate, channels: profile.channels).write(to: url)
            return url
        case .opus, .imaAdpcm:
            // Keep the raw dump so it can be analysed offline with tools/decode_dump.py.
            let url = tmp.appendingPathComponent("\(name).\(profile.audioFormat.rawValue).bin")
            try data.write(to: url)
            throw BLEManager.TransferError.unsupportedFormat("\(profile.audioFormat.rawValue) (volcado guardado en \(url.lastPathComponent))")
        }
    }

    /// Detects common containers by magic bytes so a mis-set extension still plays.
    static func sniffExtension(_ d: Data) -> String? {
        let b = [UInt8](d.prefix(12))
        guard b.count >= 4 else { return nil }
        if b[0...3] == [0x52, 0x49, 0x46, 0x46] { return "wav" }             // RIFF
        if b[0...3] == [0x4F, 0x67, 0x67, 0x53] { return "ogg" }             // OggS (Opus)
        if b[0...2] == [0x49, 0x44, 0x33] || (b[0] == 0xFF && b[1] & 0xE0 == 0xE0) { return "mp3" }
        if b.count >= 8, b[4...7] == [0x66, 0x74, 0x79, 0x70] { return "m4a" } // ftyp
        if b[0...3] == [0x23, 0x21, 0x41, 0x4D] { return "amr" }             // #!AMR
        return nil
    }

    static func wav(pcm16 pcm: Data, sampleRate: Int, channels: Int) -> Data {
        var h = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; h.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; h.append(Data(bytes: &x, count: 2)) }
        h.append(contentsOf: Array("RIFF".utf8)); u32(36 + pcm.count)
        h.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(channels)
        u32(sampleRate); u32(sampleRate * channels * 2); u16(channels * 2); u16(16)
        h.append(contentsOf: Array("data".utf8)); u32(pcm.count)
        return h + pcm
    }
}
