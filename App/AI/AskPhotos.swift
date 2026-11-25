import Foundation
import FoundationModels
import FirebaseAILogic
import TidyCore

@Generable struct PhotoAnswer {
    @Guide(description: "The answer in one or two short sentences, quoting exact values such as a password, time, amount or place. Never just true or false.")
    var answer: String
    @Guide(description: "Numbers of the photo texts the answer comes from")
    var sources: [Int]
    @Guide(description: "True only if the numbered photo texts contain the answer")
    var found: Bool

    /// The small model sometimes writes the yes/no flag as the answer.
    var usable: Bool { !["", "true", "false", "yes", "no"].contains(answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
}

@Generable struct AlbumNames {
    @Guide(description: "One short, warm album name per numbered line, in the same order, 1 to 3 words, no emoji")
    var names: [String]
}

struct AskResult: Equatable {
    var answer: String
    var sourceIDs: [String]
    var onDevice: Bool
}

enum AskConfig {
    static let snippets = 5
    static let snippetChars = 500
    static let instructions = """
    Answer the user's question using only the numbered texts read from photos on their iPhone. \
    Quote exact values. If the texts do not contain the answer, set found to false and say so briefly. Never guess.
    """
    static let namingInstructions = """
    Name photo albums. Each line gives what the photos show and how many there are. \
    Reply with one short, friendly name per line, e.g. "dog - 34 photos" -> "Good Dogs", "food - 20 photos" -> "Food Diary".
    """
}

extension HybridJudge {
    /// Ask your photos: on-device retrieval picks the likeliest texts; the on-device model answers from them only.
    /// IDs and cards are never searched here. On-device only: photo text can hold passwords and codes masking can't catch.
    func ask(_ question: String, items: [IndexedItem]) async throws -> AskResult? {
        let docs = items.filter { $0.verdict.sensitive == nil && !$0.record.ocrText.isEmpty }
            .map { (id: $0.record.id, text: [$0.verdict.savedInfo?.title, $0.verdict.reason, $0.record.ocrText].compactMap { $0 }.joined(separator: " · ")) }
        let ids = await Task.detached(priority: .userInitiated) { retrieve(question, from: docs, limit: AskConfig.snippets) }.value
        guard !ids.isEmpty else { return nil }
        guard status == .available else {
            return AskResult(answer: "Ask needs on-device AI. Text from your photos is never sent to the cloud.", sourceIDs: [ids[0]], onDevice: true)
        }
        let byID = Dictionary(docs.map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a })
        let dates = Dictionary(items.map { ($0.record.id, $0.record.createdAt) }, uniquingKeysWith: { a, _ in a })
        let lines = ids.enumerated().map { i, id in
            let text = String((byID[id] ?? "").prefix(AskConfig.snippetChars))
            return "[\(i + 1)] (\(dates[id]?.formatted(date: .abbreviated, time: .omitted) ?? "")) \(text)"
        }
        let prompt = "Question: \(question)\n\n" + lines.joined(separator: "\n")
        var r = try await respond(to: prompt, instructions: AskConfig.instructions, generating: PhotoAnswer.self,
                                  allowCloud: false, task: "ask your photos")
        if !r.usable {   // one retry, then point at the best photo instead of showing a bare flag
            r = try await respond(to: prompt, instructions: AskConfig.instructions, generating: PhotoAnswer.self, allowCloud: false, task: "ask your photos")
            if !r.usable { return AskResult(answer: "This photo looks like the answer.", sourceIDs: [ids[0]], onDevice: true) }
        }
        guard r.found else { return AskResult(answer: r.answer, sourceIDs: [], onDevice: true) }
        let used = r.sources.compactMap { ids.indices.contains($0 - 1) ? ids[$0 - 1] : nil }
        return AskResult(answer: r.answer, sourceIDs: used.isEmpty ? [ids[0]] : used, onDevice: true)
    }

    /// Friendly names for suggested albums. Sends only generic words and counts ("dog - 34 photos").
    func nameSuggestions(_ s: [AlbumSuggestion]) async -> [String]? {
        guard !s.isEmpty else { return [] }
        let prompt = s.enumerated().map { i, x in "\(i + 1). \(x.spec.name.lowercased()) - \(x.ids.count) photos" }.joined(separator: "\n")
        guard let r = try? await respond(to: prompt, instructions: AskConfig.namingInstructions, generating: AlbumNames.self,
                                         allowCloud: true, task: "album names"),
              r.names.count == s.count else { return nil }
        return r.names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
