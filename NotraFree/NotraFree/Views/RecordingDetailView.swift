import SwiftUI
import AVFoundation

struct RecordingDetailView: View {
    let recordingId: UUID
    @EnvironmentObject var store: RecordingStore
    @EnvironmentObject var drive: GoogleDriveService
    @State private var player: AVAudioPlayer?
    @State private var playing = false
    @State private var busy: String?
    @State private var error: String?
    @State private var tab = 0
    @Environment(\.isUnfolded) private var isUnfolded

    private var rec: Recording? { store.recordings.first { $0.id == recordingId } }

    var body: some View {
        if let rec {
            Form {
                Section {
                    TextField("Título", text: Binding(
                        get: { rec.title },
                        set: { var r = rec; r.title = $0; store.update(r) }))
                        .font(.headline)
                    HStack {
                        Button { togglePlay(rec) } label: {
                            Label(playing ? "Pausa" : "Reproducir", systemImage: playing ? "pause.fill" : "play.fill")
                        }
                        Spacer()
                        Text(Duration.seconds(rec.duration).formatted(.time(pattern: .minuteSecond)))
                            .foregroundStyle(.secondary)
                    }
                    ShareLink(item: store.url(for: rec)) { Label("Compartir audio", systemImage: "square.and.arrow.up") }
                }

                Section {
                    Button { run("Transcribiendo…") { _ = try await Processor.transcribe(rec, store: store) } }
                        label: { Label(rec.transcript == nil ? "Transcribir (gratis, en el iPhone)" : "Volver a transcribir", systemImage: "text.bubble") }
                    Button { run("Resumiendo…") { _ = await Processor.summarize(rec, store: store) } }
                        label: { Label("Resumir con IA local", systemImage: "sparkles") }
                        .disabled(rec.transcript == nil)
                    Button { run("Subiendo a Drive…") { _ = try await Processor.sync(rec, store: store, drive: drive) } }
                        label: { Label(rec.isSynced ? "Actualizar en Google Drive" : "Subir a Google Drive", systemImage: "icloud.and.arrow.up") }
                        .disabled(!drive.isSignedIn)
                    if let busy { HStack { ProgressView(); Text(busy) } }
                }

                if isUnfolded {
                    // Large inner screen: summary and transcript side by side.
                    Section {
                        HStack(alignment: .top, spacing: 16) {
                            column("Resumen", rec.summary)
                            Divider()
                            column("Transcripción", rec.transcript)
                        }
                    }
                } else {
                    Section {
                        Picker("", selection: $tab) {
                            Text("Resumen").tag(0)
                            Text("Transcripción").tag(1)
                        }.pickerStyle(.segmented)
                        Text((tab == 0 ? rec.summary : rec.transcript) ?? "—")
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(rec.title)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: .constant(error != nil), actions: { Button("OK") { error = nil } },
                   message: { Text(error ?? "") })
            .onDisappear { player?.stop() }
        }
    }

    private func column(_ title: String, _ text: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text ?? "—").textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func togglePlay(_ rec: Recording) {
        if playing { player?.pause(); playing = false; return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            if player == nil { player = try AVAudioPlayer(contentsOf: store.url(for: rec)) }
            player?.play()
            playing = true
        } catch { self.error = error.localizedDescription }
    }

    private func run(_ label: String, _ work: @escaping () async throws -> Void) {
        busy = label
        Task {
            do { try await work() } catch { self.error = error.localizedDescription }
            busy = nil
        }
    }
}
