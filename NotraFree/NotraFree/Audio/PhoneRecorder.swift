import Foundation
import AVFoundation

/// Fallback: record directly with the iPhone microphone.
@MainActor
final class PhoneRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("iphone-\(Int(Date().timeIntervalSince1970)).m4a")
        recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])
        recorder?.record()
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed = self?.recorder?.currentTime ?? 0 }
        }
    }

    func stop() -> URL? {
        timer?.invalidate()
        let url = recorder?.url
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        return url
    }
}
