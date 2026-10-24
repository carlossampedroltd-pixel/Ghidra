import SwiftUI
import CoreBluetooth

struct DeviceView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: RecordingStore
    @EnvironmentObject var drive: GoogleDriveService
    @State private var index = 0
    @State private var downloading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if ble.state != .poweredOn {
                    Label("Bluetooth no disponible (\(String(describing: ble.state.rawValue)))", systemImage: "exclamationmark.triangle")
                }

                if let p = ble.connected {
                    Section("Conectado") {
                        LabeledContent("Dispositivo", value: p.name ?? p.identifier.uuidString)
                        Button("Desconectar", role: .destructive) { ble.disconnect() }
                    }
                    Section("Descargar grabación") {
                        Stepper("Grabación nº \(index)", value: $index, in: 0...999)
                        Button {
                            download()
                        } label: {
                            if downloading {
                                HStack { ProgressView(); Text("\(ble.transferProgress / 1024) KB recibidos") }
                            } else {
                                Label("Descargar al iPhone", systemImage: "arrow.down.circle")
                            }
                        }.disabled(downloading)
                        Text("Requiere el perfil BLE completo (Ajustes › Perfil BLE).").font(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        NavigationLink("Explorador GATT y consola") { GATTExplorerView() }
                    } footer: {
                        Text("Herramienta de ingeniería inversa: ver servicios, enviar comandos hex y registrar respuestas.")
                    }
                } else {
                    Section {
                        Button(ble.isScanning ? "Detener búsqueda" : "Buscar grabadora") {
                            ble.isScanning ? ble.stopScan() : ble.startScan()
                        }
                    }
                    Section("Dispositivos cercanos") {
                        ForEach(ble.discovered) { d in
                            Button { ble.connect(d) } label: {
                                HStack {
                                    Image(systemName: d.looksLikeNotra ? "star.fill" : "dot.radiowaves.right")
                                        .foregroundStyle(d.looksLikeNotra ? .yellow : .secondary)
                                    Text(d.name)
                                    Spacer()
                                    Text("\(d.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section {
                        Text("Si la grabadora no aparece: ciérrala en la app oficial de Boya (solo admite una conexión) y comprueba que está encendida.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Notra NEO")
            .alert("Aviso", isPresented: .constant(message != nil), actions: { Button("OK") { message = nil } },
                   message: { Text(message ?? "") })
        }
    }

    private func download() {
        downloading = true
        Task {
            defer { downloading = false }
            do {
                let url = try await ble.downloadRecording(index: index)
                let rec = try await store.add(audioAt: url, title: "Notra #\(index)", origin: .device, move: true)
                let errors = await Processor.runAll(rec, store: store, drive: drive)
                message = errors.isEmpty ? "Grabación descargada y procesada." : errors.joined(separator: "\n")
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

struct GATTExplorerView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var hex = ""
    @State private var target: CBUUID?

    private var chars: [CBCharacteristic] { ble.services.compactMap(\.characteristics).flatMap { $0 } }

    var body: some View {
        List {
            Section("Servicios") {
                ForEach(ble.services, id: \.uuid) { s in
                    DisclosureGroup(s.uuid.uuidString) {
                        ForEach(s.characteristics ?? [], id: \.uuid) { c in
                            VStack(alignment: .leading) {
                                Text(c.uuid.uuidString).font(.caption.monospaced())
                                Text(c.properties.describe).font(.caption2).foregroundStyle(.secondary)
                                HStack {
                                    if c.properties.contains(.read) { Button("Leer") { ble.read(c) }.buttonStyle(.bordered) }
                                    Button("Usar como write") { ble.profile.writeUUID = c.uuid.uuidString; target = c.uuid }
                                        .buttonStyle(.bordered)
                                    Button("Usar como notify") { ble.profile.notifyUUID = c.uuid.uuidString; ble.profile.serviceUUID = s.uuid.uuidString }
                                        .buttonStyle(.bordered)
                                }.font(.caption2)
                            }
                        }
                    }
                }
            }
            Section("Enviar comando") {
                Picker("Destino", selection: $target) {
                    Text("—").tag(CBUUID?.none)
                    ForEach(chars.filter { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }, id: \.uuid) {
                        Text($0.uuid.uuidString).tag(Optional($0.uuid))
                    }
                }
                TextField("hex, p.ej. aa 55 01 00", text: $hex)
                    .font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Enviar") {
                    if let t = target, let c = chars.first(where: { $0.uuid == t }) { ble.write(hex: hex, to: c) }
                }.disabled(target == nil || hex.isEmpty)
            }
            Section {
                ForEach(ble.log.suffix(300).reversed()) { l in
                    Text("\(l.direction.rawValue) \(l.characteristic.map { String($0.prefix(8)) + " " } ?? "")\(l.text)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(l.direction == .tx ? .blue : l.direction == .rx ? .primary : .secondary)
                }
            } header: {
                HStack {
                    Text("Registro")
                    Spacer()
                    ShareLink(item: ble.exportLog()) { Image(systemName: "square.and.arrow.up") }
                    Button { ble.clearLog() } label: { Image(systemName: "trash") }
                }
            }
        }
        .navigationTitle("Explorador GATT")
        .onAppear { target = ble.profile.writeUUID.map(CBUUID.init(string:)) }
    }
}
