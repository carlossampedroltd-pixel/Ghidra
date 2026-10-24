import Foundation
import CoreBluetooth

/// CoreBluetooth central that doubles as an on-phone protocol explorer:
/// it discovers every service/characteristic, subscribes to every notify
/// characteristic and logs all traffic, so you can poke the recorder with
/// hex commands and watch the answers while reverse engineering it.
@MainActor
final class BLEManager: NSObject, ObservableObject {
    struct Discovered: Identifiable {
        let id: UUID
        let peripheral: CBPeripheral
        var name: String
        var rssi: Int
        var looksLikeNotra: Bool
    }

    struct LogLine: Identifiable {
        enum Direction: String { case tx = "→", rx = "←", info = "•" }
        let id = UUID()
        let date = Date()
        let direction: Direction
        let characteristic: String?
        let text: String
    }

    enum TransferError: LocalizedError {
        case notConnected, profileIncomplete(String), unsupportedFormat(String), empty
        var errorDescription: String? {
            switch self {
            case .notConnected: return "La grabadora no está conectada."
            case .profileIncomplete(let f): return "Falta '\(f)' en el perfil BLE. Revisa docs/REVERSE_ENGINEERING.md."
            case .unsupportedFormat(let f): return "Formato \(f) aún no implementado."
            case .empty: return "No se recibieron datos."
            }
        }
    }

    @Published var state: CBManagerState = .unknown
    @Published var isScanning = false
    @Published var discovered: [Discovered] = []
    @Published var connected: CBPeripheral?
    @Published var services: [CBService] = []
    @Published var log: [LogLine] = []
    @Published var transferProgress: Int = 0   // bytes received in current transfer
    @Published var profile = DeviceProfile.load() { didSet { profile.save() } }

    private var central: CBCentralManager!
    private var transferBuffer = Data()
    private var transferActive = false
    private var transferPackets = 0
    private var lastPacketAt = Date()

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Scan / connect

    func startScan() {
        guard state == .poweredOn else { return }
        discovered.removeAll()
        // Scan with no service filter: the Notra's service UUID is unknown until captured.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
        info("Escaneando…")
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func connect(_ d: Discovered) {
        stopScan()
        info("Conectando a \(d.name)…")
        central.connect(d.peripheral)
    }

    func disconnect() {
        if let p = connected { central.cancelPeripheralConnection(p) }
    }

    // MARK: - Raw I/O

    func characteristic(_ uuid: String?) -> CBCharacteristic? {
        guard let uuid, DeviceProfile.isValidUUID(uuid) else { return nil }
        let target = CBUUID(string: uuid)
        return services.lazy.compactMap(\.characteristics).joined().first { $0.uuid == target }
    }

    func write(hex: String, to char: CBCharacteristic, withResponse: Bool? = nil) {
        guard let data = Data(hexString: hex) else { info("Hex inválido: \(hex)"); return }
        write(data, to: char, withResponse: withResponse)
    }

    func write(_ data: Data, to char: CBCharacteristic, withResponse: Bool? = nil) {
        guard let p = connected else { return }
        let wr = withResponse ?? (char.properties.contains(.write) && !char.properties.contains(.writeWithoutResponse))
        p.writeValue(data, for: char, type: wr ? .withResponse : .withoutResponse)
        log.append(.init(direction: .tx, characteristic: char.uuid.uuidString, text: data.hexString))
    }

    func read(_ char: CBCharacteristic) { connected?.readValue(for: char) }

    func clearLog() { log.removeAll() }

    func exportLog() -> URL {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let text = log.map { "\(fmt.string(from: $0.date)) \($0.direction.rawValue) [\($0.characteristic ?? "-")] \($0.text)" }
            .joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notra-ble-log.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Recording download (profile driven)

    /// Asks the device for recording `index` and collects notifications until the
    /// end marker or the idle timeout. Returns a playable audio file URL.
    func downloadRecording(index: Int) async throws -> URL {
        guard connected != nil else { throw TransferError.notConnected }
        guard let writeChar = characteristic(profile.writeUUID) else { throw TransferError.profileIncomplete("writeUUID") }
        guard characteristic(profile.notifyUUID) != nil else { throw TransferError.profileIncomplete("notifyUUID") }
        guard let cmd = profile.downloadCommand(index: index) else { throw TransferError.profileIncomplete("downloadCommandHex") }

        transferBuffer = Data()
        transferProgress = 0
        transferPackets = 0
        transferActive = true
        lastPacketAt = Date()
        write(cmd, to: writeChar, withResponse: profile.writeWithResponse)

        while transferActive {
            try await Task.sleep(nanoseconds: 200_000_000)
            if Date().timeIntervalSince(lastPacketAt) > profile.idleTimeout { transferActive = false }
        }
        guard !transferBuffer.isEmpty else { throw TransferError.empty }
        info("Transferencia completa: \(transferBuffer.count) bytes")
        return try AudioPacker.makeFile(from: transferBuffer, profile: profile)
    }

    private func handleTransferPacket(_ data: Data, from char: CBCharacteristic) {
        guard transferActive, isNotifyChar(char) else { return }
        lastPacketAt = Date()
        if let end = profile.endOfTransferHex.flatMap(Data.init(hexString:)), data.starts(with: end) {
            transferActive = false
            return
        }
        let payload = data.dropFirst(min(profile.headerBytesPerPacket, data.count))
        transferBuffer.append(payload)
        transferProgress = transferBuffer.count
        if let ack = profile.ackCommandHex, let w = characteristic(profile.writeUUID),
           let ackData = Data(hexString: ack) {
            connected?.writeValue(ackData, for: w, type: profile.writeWithResponse ? .withResponse : .withoutResponse)
        }
    }

    private func isNotifyChar(_ c: CBCharacteristic) -> Bool {
        guard let n = profile.notifyUUID, DeviceProfile.isValidUUID(n) else { return false }
        return c.uuid.uuidString.caseInsensitiveCompare(CBUUID(string: n).uuidString) == .orderedSame
    }

    private func info(_ s: String) {
        log.append(.init(direction: .info, characteristic: nil, text: s))
    }
}

// MARK: - CBCentralManagerDelegate / CBPeripheralDelegate

extension BLEManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { state = central.state }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Sin nombre"
            let looks = profile.namePrefixes.contains { name.localizedCaseInsensitiveContains($0) }
            let d = Discovered(id: peripheral.identifier, peripheral: peripheral, name: name,
                               rssi: RSSI.intValue, looksLikeNotra: looks)
            if let i = discovered.firstIndex(where: { $0.id == d.id }) {
                discovered[i] = d
            } else {
                discovered.append(d)
            }
            discovered.sort { ($0.looksLikeNotra ? 1 : 0, $0.rssi) > ($1.looksLikeNotra ? 1 : 0, $1.rssi) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            connected = peripheral
            services = []
            peripheral.delegate = self
            info("Conectado. MTU máx. sin respuesta: \(peripheral.maximumWriteValueLength(for: .withoutResponse))")
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { info("Fallo al conectar: \(error?.localizedDescription ?? "-")") }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            connected = nil
            services = []
            transferActive = false
            info("Desconectado \(error.map { "(\($0.localizedDescription))" } ?? "")")
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            for s in peripheral.services ?? [] {
                info("Servicio \(s.uuid.uuidString)")
                peripheral.discoverCharacteristics(nil, for: s)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for c in service.characteristics ?? [] {
                info("  Char \(c.uuid.uuidString) props=\(c.properties.describe)")
                if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: c)
                }
                if c.properties.contains(.read) { peripheral.readValue(for: c) }
            }
            services = peripheral.services ?? []
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let v = characteristic.value else { return }
            if transferActive && isNotifyChar(characteristic) {
                // Don't flood the log during bulk transfers; log only every 50th packet.
                transferPackets += 1
                if transferPackets % 50 == 1 {
                    log.append(.init(direction: .rx, characteristic: characteristic.uuid.uuidString,
                                     text: "[#\(transferPackets), \(transferProgress) B] \(v.prefix(24).hexString)…"))
                }
            } else {
                let printable = v.allSatisfy { (0x20...0x7e).contains($0) }
                let ascii = printable ? " \"\(String(decoding: v, as: UTF8.self))\"" : ""
                log.append(.init(direction: .rx, characteristic: characteristic.uuid.uuidString, text: v.hexString + ascii))
            }
            handleTransferPacket(v, from: characteristic)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            MainActor.assumeIsolated { info("Error de escritura en \(characteristic.uuid): \(error.localizedDescription)") }
        }
    }
}

extension CBCharacteristicProperties {
    var describe: String {
        var p: [String] = []
        if contains(.read) { p.append("read") }
        if contains(.write) { p.append("write") }
        if contains(.writeWithoutResponse) { p.append("writeNoResp") }
        if contains(.notify) { p.append("notify") }
        if contains(.indicate) { p.append("indicate") }
        return p.joined(separator: ",")
    }
}
