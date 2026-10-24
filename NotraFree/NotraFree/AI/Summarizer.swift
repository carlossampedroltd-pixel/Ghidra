import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Free, on-device summaries using Apple Intelligence (iOS 26+, compatible iPhone).
/// On older devices it falls back to a simple extractive summary.
enum Summarizer {
    static func summarize(_ transcript: String) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            do {
                let instructions = """
                    Eres un asistente que resume notas de voz. Responde en el mismo idioma \
                    que la transcripción. Formato: un título corto, un resumen de 3-5 frases, \
                    una lista de puntos clave y una lista de tareas pendientes (si las hay).
                    """
                // The on-device model has a limited context window; summarize in chunks.
                var partials: [String] = []
                for chunk in transcript.chunked(maxChars: 6000) {
                    // Fresh session per chunk so earlier chunks don't eat the context window.
                    let session = LanguageModelSession(instructions: instructions)
                    partials.append(try await session.respond(to: "Resume esta parte:\n\n\(chunk)").content)
                }
                if partials.count == 1 { return partials[0] }
                let merged = try await LanguageModelSession().respond(
                    to: "Une estos resúmenes parciales en uno solo con el mismo formato:\n\n" + partials.joined(separator: "\n---\n"))
                return merged.content
            } catch {
                return extractive(transcript) + "\n\n(Resumen IA falló: \(error.localizedDescription))"
            }
        }
        #endif
        return extractive(transcript)
    }

    /// Picks the first sentence plus the longest sentences as a crude summary.
    static func extractive(_ text: String) -> String {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 20 }
        guard let first = sentences.first else { return text }
        let top = sentences.dropFirst().sorted { $0.count > $1.count }.prefix(4)
        return ([first] + top).map { "• \($0)." }.joined(separator: "\n")
    }
}

extension String {
    func chunked(maxChars: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for word in split(separator: " ") {
            if current.count + word.count + 1 > maxChars {
                chunks.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : " ") + word
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
