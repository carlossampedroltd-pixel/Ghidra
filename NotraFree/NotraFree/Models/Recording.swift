import Foundation

enum RecordingSource: String, Codable {
    case device      // downloaded from the Notra NEO over BLE
    case imported    // imported from Files (USB / AirDrop / exported from the Boya app)
    case phone       // recorded with the iPhone microphone
    case drive       // pulled down from Google Drive
}

struct Recording: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    /// File name inside RecordingStore.audioDirectory
    var audioFileName: String
    var source: RecordingSource
    var transcript: String?
    var summary: String?
    /// Google Drive file IDs once uploaded
    var driveAudioId: String?
    var driveTranscriptId: String?

    var isSynced: Bool { driveAudioId != nil }
}
