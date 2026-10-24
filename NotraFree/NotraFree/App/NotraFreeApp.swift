import SwiftUI
import GoogleSignIn

@main
struct NotraFreeApp: App {
    @StateObject private var store = RecordingStore()
    @StateObject private var drive = GoogleDriveService()
    @StateObject private var ble = BLEManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(drive)
                .environmentObject(ble)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .task { await drive.restoreSession() }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Notas", systemImage: "waveform") }
            DeviceView()
                .tabItem { Label("Grabadora", systemImage: "dot.radiowaves.left.and.right") }
            DriveView()
                .tabItem { Label("Drive", systemImage: "externaldrive.badge.icloud") }
            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
        }
    }
}
