import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var ble: BLEManager
    @AppStorage("localeId") private var localeId = "es-ES"
    @AppStorage("autoProcess") private var autoProcess = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Procesamiento") {
                    Picker("Idioma de transcripción", selection: $localeId) {
                        Text("Español (España)").tag("es-ES")
                        Text("Español (México)").tag("es-MX")
                        Text("English (US)").tag("en-US")
                        Text("English (UK)").tag("en-GB")
                        Text("Português (BR)").tag("pt-BR")
                        Text("Français").tag("fr-FR")
                        Text("Deutsch").tag("de-DE")
                        Text("Italiano").tag("it-IT")
                    }
                    Toggle("Transcribir, resumir y subir automáticamente", isOn: $autoProcess)
                }
                Section {
                    NavigationLink("Perfil BLE de la grabadora") { ProfileEditorView() }
                } footer: {
                    Text("UUIDs y comandos obtenidos por ingeniería inversa. Ver docs/REVERSE_ENGINEERING.md.")
                }
                Section("Acerca de") {
                    Text("NotraFree no usa servidores ni la suscripción de Boya: la transcripción y el resumen se hacen en el iPhone y los archivos se guardan en tu Google Drive.")
                        .font(.caption)
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}

struct ProfileEditorView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var json = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextEditor(text: $json)
                    .font(.caption.monospaced())
                    .frame(minHeight: 380)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
            }
            Section {
                Button("Guardar") {
                    do {
                        ble.profile = try JSONDecoder().decode(DeviceProfile.self, from: Data(json.utf8))
                        error = nil
                    } catch { self.error = "JSON inválido: \(error)" }
                }
                Button("Restaurar borrador por defecto", role: .destructive) {
                    ble.profile = .notraNeoDraft
                    json = ble.profile.prettyJSON
                }
            }
        }
        .navigationTitle("Perfil BLE")
        .onAppear { json = ble.profile.prettyJSON }
    }
}
