import SwiftUI
import GoogleSignIn

@main
struct NotraFreeApp: App {
    @StateObject private var store = RecordingStore()
    @StateObject private var drive = GoogleDriveService()
    @StateObject private var ble = BLEManager()
    // App-level so a recording survives the layout switch when the Duo folds/unfolds.
    @StateObject private var phone = PhoneRecorder()

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environmentObject(store)
                .environmentObject(drive)
                .environmentObject(ble)
                .environmentObject(phone)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .task { await drive.restoreSession() }
        }
    }
}

/// Each build target picks its root: the DUO flag is set only in Config/Duo.xcconfig.
struct AppRoot: View {
    var body: some View {
        #if DUO
        DuoRootView()
        #else
        RootView()
        #endif
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
