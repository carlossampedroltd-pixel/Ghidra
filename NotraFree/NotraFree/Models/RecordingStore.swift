import Foundation
import AVFoundation

/// Local library of recordings, persisted as JSON + audio files in Documents/.
@MainActor
final class RecordingStore: ObservableObject {
    @Published private(set) var recordings: [Recording] = []

    let audioDirectory: URL
    private let indexURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        audioDirectory = docs.appendingPathComponent("Audio", isDirectory: true)
        indexURL = docs.appendingPathComponent("recordings.json")
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        load()
    }

    func url(for recording: Recording) -> URL {
        audioDirectory.appendingPathComponent(recording.audioFileName)
    }

    /// Copies (or moves) an audio file into the library and registers it.
    @discardableResult
    func add(audioAt source: URL, title: String? = nil, origin: RecordingSource,
             createdAt: Date = Date(), move: Bool = false) async throws -> Recording {
        let ext = source.pathExtension.isEmpty ? "wav" : source.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let dest = audioDirectory.appendingPathComponent(fileName)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        if move {
            try FileManager.default.moveItem(at: source, to: dest)
        } else {
            try FileManager.default.copyItem(at: source, to: dest)
        }
        let duration = (try? await AVURLAsset(url: dest).load(.duration).seconds) ?? 0
        let rec = Recording(
            title: title ?? source.deletingPathExtension().lastPathComponent,
            createdAt: createdAt,
            duration: duration.isFinite ? duration : 0,
            audioFileName: fileName,
            source: origin)
        recordings.insert(rec, at: 0)
        save()
        return rec
    }

    func update(_ rec: Recording) {
        guard let i = recordings.firstIndex(where: { $0.id == rec.id }) else { return }
        recordings[i] = rec
        save()
    }

    func delete(_ rec: Recording) {
        try? FileManager.default.removeItem(at: url(for: rec))
        recordings.removeAll { $0.id == rec.id }
        save()
    }

    func contains(driveAudioId: String) -> Bool {
        recordings.contains { $0.driveAudioId == driveAudioId }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        recordings = (try? decoder.decode([Recording].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(recordings).write(to: indexURL, options: .atomic)
    }
}
