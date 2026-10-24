import Foundation

/// Transcribe → summarize → upload to Drive, according to user settings.
@MainActor
enum Processor {
    static var localeId: String { UserDefaults.standard.string(forKey: "localeId") ?? "es-ES" }
    static var autoProcess: Bool { UserDefaults.standard.object(forKey: "autoProcess") as? Bool ?? true }

    static func transcribe(_ rec: Recording, store: RecordingStore) async throws -> Recording {
        var rec = rec
        rec.transcript = try await Transcriber.transcribe(url: store.url(for: rec), localeId: localeId)
        store.update(rec)
        return rec
    }

    static func summarize(_ rec: Recording, store: RecordingStore) async -> Recording {
        guard let t = rec.transcript, !t.isEmpty else { return rec }
        var rec = rec
        rec.summary = await Summarizer.summarize(t)
        store.update(rec)
        return rec
    }

    static func sync(_ rec: Recording, store: RecordingStore, drive: GoogleDriveService) async throws -> Recording {
        let rec = try await drive.sync(rec, audioURL: store.url(for: rec))
        store.update(rec)
        return rec
    }

    /// Full pipeline for a freshly added recording. Errors are returned, not thrown,
    /// so one failing step (e.g. not signed into Drive) doesn't hide the others.
    static func runAll(_ rec: Recording, store: RecordingStore, drive: GoogleDriveService) async -> [String] {
        guard autoProcess else { return [] }
        var errors: [String] = []
        var rec = rec
        do { rec = try await transcribe(rec, store: store) } catch { errors.append(error.localizedDescription) }
        rec = await summarize(rec, store: store)
        if drive.isSignedIn {
            do { _ = try await sync(rec, store: store, drive: drive) } catch { errors.append(error.localizedDescription) }
        }
        return errors
    }
}
