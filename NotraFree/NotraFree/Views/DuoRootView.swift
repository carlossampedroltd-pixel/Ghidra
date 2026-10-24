import SwiftUI

/// True while the iPhone Duo is unfolded (or any window wide enough for two columns).
private struct IsUnfoldedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isUnfolded: Bool {
        get { self[IsUnfoldedKey.self] }
        set { self[IsUnfoldedKey.self] = newValue }
    }
}

/// Root for the iPhone Duo build. Folded (5.4" outer screen) it behaves like the
/// regular tab layout; unfolded (7.6" inner screen) it switches to a split view:
/// sections | notes list | note detail. The layout follows the available width,
/// not the device model, so it also adapts to Split View with another app.
struct DuoRootView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case notes = "Notas", device = "Grabadora", drive = "Drive", settings = "Ajustes"
        var id: Self { self }
        var icon: String {
            switch self {
            case .notes: return "waveform"
            case .device: return "dot.radiowaves.left.and.right"
            case .drive: return "externaldrive.badge.icloud"
            case .settings: return "gearshape"
            }
        }
    }

    /// Width above which we treat the screen as unfolded. The outer screen and
    /// a half-width Split View stay below it; the open inner screen is above it.
    static let unfoldedMinWidth: CGFloat = 700

    @State private var section: Pane? = .notes
    @State private var selectedRecording: UUID?

    var body: some View {
        GeometryReader { geo in
            let unfolded = geo.size.width >= Self.unfoldedMinWidth
            Group {
                if unfolded {
                    splitLayout
                } else {
                    RootView()
                }
            }
            .environment(\.isUnfolded, unfolded)
            .animation(.default, value: unfolded)
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationTitle("NotraFree")
        } content: {
            switch section ?? .notes {
            case .notes: LibraryView(selection: $selectedRecording)
            case .device: DeviceView()
            case .drive: DriveView()
            case .settings: SettingsView()
            }
        } detail: {
            if section == .notes, let id = selectedRecording {
                NavigationStack { RecordingDetailView(recordingId: id) }
                    .id(id)  // reset player/state when switching notes
            } else {
                ContentUnavailableView("Elige una nota", systemImage: "waveform",
                                       description: Text("La transcripción y el resumen aparecen aquí, uno al lado del otro."))
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
