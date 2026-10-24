import SwiftUI

struct DriveView: View {
    @EnvironmentObject var drive: GoogleDriveService
    @EnvironmentObject var store: RecordingStore
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Cuenta") {
                    if drive.isSignedIn {
                        LabeledContent("Google", value: drive.email ?? "—")
                        TextField("Carpeta en Drive", text: $drive.folderName)
                        Button("Subir todo lo pendiente") { syncAll() }
                        Button("Cerrar sesión", role: .destructive) { drive.signOut() }
                    } else {
                        Button { Task { do { try await drive.signIn() } catch { message = error.localizedDescription } } } label: {
                            Label("Iniciar sesión con Google", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }
                if drive.isSignedIn {
                    Section("En Drive / \(drive.folderName)") {
                        ForEach(drive.remoteFiles) { f in
                            HStack {
                                Image(systemName: f.isAudio ? "waveform" : "doc.text")
                                VStack(alignment: .leading) {
                                    Text(f.name).lineLimit(1)
                                    if let s = f.size, let n = Int(s) {
                                        Text(ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if f.isAudio && !store.contains(driveAudioId: f.id) {
                                    Button { pull(f) } label: { Image(systemName: "arrow.down.circle") }
                                }
                            }
                        }
                    }
                }
                if loading { ProgressView() }
            }
            .navigationTitle("Google Drive")
            .refreshable { await refresh() }
            .task(id: drive.isSignedIn) { await refresh() }
            .alert("Aviso", isPresented: .constant(message != nil), actions: { Button("OK") { message = nil } },
                   message: { Text(message ?? "") })
        }
    }

    private func refresh() async {
        guard drive.isSignedIn else { return }
        do { try await drive.refreshRemote() } catch { message = error.localizedDescription }
    }

    private func pull(_ f: GoogleDriveService.DriveFile) {
        loading = true
        Task {
            defer { loading = false }
            do {
                let url = try await drive.download(f)
                var rec = try await store.add(audioAt: url, origin: .drive, move: true)
                rec.driveAudioId = f.id
                store.update(rec)
            } catch { message = error.localizedDescription }
        }
    }

    private func syncAll() {
        loading = true
        Task {
            defer { loading = false }
            var failures = 0
            for rec in store.recordings where !rec.isSynced {
                do { _ = try await Processor.sync(rec, store: store, drive: drive) } catch { failures += 1 }
            }
            await refresh()
            message = failures == 0 ? "Todo sincronizado." : "\(failures) archivo(s) fallaron."
        }
    }
}
