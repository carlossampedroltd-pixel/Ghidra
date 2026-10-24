import Foundation
import UIKit
import GoogleSignIn

/// Minimal Google Drive v3 REST client. Stores everything in a "Boya Notra" folder
/// in YOUR Drive, using the `drive.file` scope (the app only sees files it created).
@MainActor
final class GoogleDriveService: ObservableObject {
    struct DriveFile: Identifiable, Decodable, Hashable {
        let id: String
        let name: String
        let mimeType: String
        let createdTime: String?
        let size: String?
    }

    enum DriveError: LocalizedError {
        case notSignedIn, http(Int, String)
        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Inicia sesión con Google primero."
            case .http(let c, let b): return "Drive HTTP \(c): \(b)"
            }
        }
    }

    static let scope = "https://www.googleapis.com/auth/drive.file"

    @Published private(set) var user: GIDGoogleUser?
    @Published var folderName: String = UserDefaults.standard.string(forKey: "driveFolder") ?? "Boya Notra" {
        didSet { UserDefaults.standard.set(folderName, forKey: "driveFolder"); folderId = nil }
    }
    @Published private(set) var remoteFiles: [DriveFile] = []

    private var folderId: String?

    var isSignedIn: Bool { user != nil }
    var email: String? { user?.profile?.email }

    // MARK: Auth

    func restoreSession() async {
        user = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
    }

    func signIn() async throws {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: root, hint: nil, additionalScopes: [Self.scope])
        user = result.user
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        user = nil
        folderId = nil
        remoteFiles = []
    }

    private func token() async throws -> String {
        guard let user else { throw DriveError.notSignedIn }
        let fresh = try await user.refreshTokensIfNeeded()
        return fresh.accessToken.tokenString
    }

    // MARK: REST helpers

    private func send(_ req: URLRequest) async throws -> Data {
        var req = req
        req.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw DriveError.http(code, String(decoding: data.prefix(500), as: UTF8.self))
        }
        return data
    }

    private func ensureFolder() async throws -> String {
        if let folderId { return folderId }
        let q = "name = '\(folderName.replacingOccurrences(of: "'", with: "\\'"))' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [.init(name: "q", value: q), .init(name: "fields", value: "files(id,name)")]
        struct List: Decodable { let files: [DriveFile.Minimal] }
        let list = try JSONDecoder().decode(List.self, from: try await send(URLRequest(url: comps.url!)))
        if let existing = list.files.first {
            folderId = existing.id
            return existing.id
        }
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": folderName, "mimeType": "application/vnd.google-apps.folder"])
        let created = try JSONDecoder().decode(DriveFile.Minimal.self, from: try await send(req))
        folderId = created.id
        return created.id
    }

    // MARK: Public API

    /// Uploads (or replaces, when `existingId` is set) a file in the Drive folder. Returns its id.
    func upload(data: Data, name: String, mimeType: String, existingId: String? = nil) async throws -> String {
        let boundary = "notra-\(UUID().uuidString)"
        var meta: [String: Any] = ["name": name]
        if existingId == nil { meta["parents"] = [try await ensureFolder()] }
        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }
        add("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(try JSONSerialization.data(withJSONObject: meta))
        add("\r\n--\(boundary)\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        add("\r\n--\(boundary)--\r\n")

        let base = existingId.map { "https://www.googleapis.com/upload/drive/v3/files/\($0)" }
            ?? "https://www.googleapis.com/upload/drive/v3/files"
        var req = URLRequest(url: URL(string: "\(base)?uploadType=multipart&fields=id")!)
        req.httpMethod = existingId == nil ? "POST" : "PATCH"
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return try JSONDecoder().decode(DriveFile.Minimal.self, from: try await send(req)).id
    }

    /// Uploads the audio and a Markdown note (transcript + summary) for a recording.
    func sync(_ rec: Recording, audioURL: URL) async throws -> Recording {
        var rec = rec
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH.mm"
        let stamp = fmt.string(from: rec.createdAt)
        let base = "\(stamp) \(rec.title)".replacingOccurrences(of: "/", with: "-")
        if rec.driveAudioId == nil {
            rec.driveAudioId = try await upload(data: try Data(contentsOf: audioURL),
                                                name: "\(base).\(audioURL.pathExtension)",
                                                mimeType: Self.mime(for: audioURL.pathExtension))
        }
        if rec.transcript != nil || rec.summary != nil {
            let md = """
            # \(rec.title)
            Fecha: \(rec.createdAt.formatted(date: .long, time: .shortened))
            Duración: \(Int(rec.duration / 60)) min \(Int(rec.duration) % 60) s

            ## Resumen
            \(rec.summary ?? "_(sin resumen)_")

            ## Transcripción
            \(rec.transcript ?? "_(sin transcripción)_")
            """
            rec.driveTranscriptId = try await upload(data: Data(md.utf8), name: "\(base).md",
                                                     mimeType: "text/markdown", existingId: rec.driveTranscriptId)
        }
        return rec
    }

    func refreshRemote() async throws {
        let folder = try await ensureFolder()
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [
            .init(name: "q", value: "'\(folder)' in parents and trashed = false"),
            .init(name: "orderBy", value: "createdTime desc"),
            .init(name: "pageSize", value: "200"),
            .init(name: "fields", value: "files(id,name,mimeType,createdTime,size)")]
        struct List: Decodable { let files: [DriveFile] }
        remoteFiles = try JSONDecoder().decode(List.self, from: try await send(URLRequest(url: comps.url!))).files
    }

    func download(_ file: DriveFile) async throws -> URL {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(file.id)?alt=media")!
        let data = try await send(URLRequest(url: url))
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
        try data.write(to: dest)
        return dest
    }

    static func mime(for ext: String) -> String {
        switch ext.lowercased() {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "ogg", "opus": return "audio/ogg"
        case "amr": return "audio/amr"
        default: return "application/octet-stream"
        }
    }
}

extension GoogleDriveService.DriveFile {
    struct Minimal: Decodable { let id: String }
    var isAudio: Bool { mimeType.hasPrefix("audio/") }
}
