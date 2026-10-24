import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    /// When set (iPhone Duo unfolded), the list drives the detail column of a
    /// split view instead of pushing onto its own navigation stack.
    var selection: Binding<UUID?>? = nil

    @EnvironmentObject var store: RecordingStore
    @EnvironmentObject var drive: GoogleDriveService
    @EnvironmentObject var phone: PhoneRecorder
    @State private var importing = false
    @State private var search = ""
    @State private var message: String?

    var filtered: [Recording] {
        guard !search.isEmpty else { return store.recordings }
        return store.recordings.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || ($0.transcript?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        if selection == nil {
            NavigationStack {
                content.navigationDestination(for: Recording.self) { RecordingDetailView(recordingId: $0.id) }
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private var list: some View {
        if let selection {
            List(selection: selection) { rows(linked: false) }
        } else {
            List { rows(linked: true) }
        }
    }

    @ViewBuilder
    private func rows(linked: Bool) -> some View {
        if phone.isRecording {
            HStack {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
                Text("Grabando con iPhone… \(Duration.seconds(phone.elapsed).formatted(.time(pattern: .minuteSecond)))")
            }
        }
        ForEach(filtered) { rec in
            if linked {
                NavigationLink(value: rec) { RecordingRow(rec: rec) }
            } else {
                RecordingRow(rec: rec).tag(rec.id)
            }
        }
        .onDelete { idx in idx.map { filtered[$0] }.forEach(store.delete) }
    }

    private var content: some View {
        list
            .overlay {
                if store.recordings.isEmpty && !phone.isRecording {
                    ContentUnavailableView("Sin notas",
                        systemImage: "waveform",
                        description: Text("Descarga desde la grabadora, importa archivos (USB-C / Archivos) o graba con el iPhone."))
                }
            }
            .searchable(text: $search, prompt: "Buscar en títulos y transcripciones")
            .navigationTitle("Notas de voz")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { importing = true } label: { Label("Importar", systemImage: "square.and.arrow.down") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { toggleRecording() } label: {
                        Label(phone.isRecording ? "Parar" : "Grabar",
                              systemImage: phone.isRecording ? "stop.circle.fill" : "mic.circle")
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .data],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task { for u in urls { await add(u, origin: .imported) } }
            }
            .alert("Aviso", isPresented: .constant(message != nil), actions: {
                Button("OK") { message = nil }
            }, message: { Text(message ?? "") })
    }

    private func toggleRecording() {
        if phone.isRecording {
            if let url = phone.stop() { Task { await add(url, origin: .phone, move: true) } }
        } else {
            Task { do { try await phone.start() } catch { message = error.localizedDescription } }
        }
    }

    private func add(_ url: URL, origin: RecordingSource, move: Bool = false) async {
        do {
            let rec = try await store.add(audioAt: url, origin: origin, move: move)
            let errors = await Processor.runAll(rec, store: store, drive: drive)
            if !errors.isEmpty { message = errors.joined(separator: "\n") }
        } catch {
            message = error.localizedDescription
        }
    }
}

struct RecordingRow: View {
    let rec: Recording
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(rec.title).font(.headline).lineLimit(1)
                Spacer()
                if rec.isSynced { Image(systemName: "checkmark.icloud").foregroundStyle(.green) }
            }
            HStack(spacing: 8) {
                Text(rec.createdAt, style: .date)
                Text(Duration.seconds(rec.duration).formatted(.time(pattern: .minuteSecond)))
                Image(systemName: icon)
            }
            .font(.caption).foregroundStyle(.secondary)
            if let s = rec.summary ?? rec.transcript {
                Text(s).font(.caption).lineLimit(2).foregroundStyle(.secondary)
            }
        }
    }
    private var icon: String {
        switch rec.source {
        case .device: return "dot.radiowaves.left.and.right"
        case .imported: return "folder"
        case .phone: return "iphone"
        case .drive: return "externaldrive"
        }
    }
}
