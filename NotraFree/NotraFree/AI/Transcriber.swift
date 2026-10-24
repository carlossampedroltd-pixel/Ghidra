import Foundation
import Speech

/// Free, on-device transcription using Apple's Speech framework.
/// No minutes quota, no subscription, audio never leaves the phone.
enum Transcriber {
    enum Failure: LocalizedError {
        case denied, unavailable(String)
        var errorDescription: String? {
            switch self {
            case .denied: return "Permiso de reconocimiento de voz denegado."
            case .unavailable(let l): return "Reconocimiento en el dispositivo no disponible para \(l). Descarga el idioma en Ajustes › General › Teclado › Dictado."
            }
        }
    }

    static func requestAuth() async -> Bool {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    static func transcribe(url: URL, localeId: String) async throws -> String {
        guard await requestAuth() else { throw Failure.denied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)),
              recognizer.supportsOnDeviceRecognition else {
            throw Failure.unavailable(localeId)
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true   // on-device = no length limit, no server
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { cont in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let error {
                    finished = true
                    cont.resume(throwing: error)
                } else if let result, result.isFinal {
                    finished = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
