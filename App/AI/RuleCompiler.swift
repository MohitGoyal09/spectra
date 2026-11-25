import Foundation
import FoundationModels
import FirebaseAILogic
import TidyCore

// Guided-generation mirror of TidyCore.RuleSpec: the model can only produce valid fields.
@Generable enum RuleKind { case camera, screenshot, forward, download, document, recording, video, received }
@Generable enum RuleJunk { case duplicate, blurry, forward, meme, expired_otp, expired_qr, old_payment, big_video, screen_recording, ai_made }
@Generable enum RuleDoc { case receipt, bill, ticket, booking, id, other }

@Generable struct RuleDraft {
    @Guide(description: "A short album name of 1 to 4 words, taken from the user's sentence")
    var name: String
    @Guide(description: "Photo kinds to include; empty if the sentence does not limit kinds")
    var kinds: [RuleKind]
    @Guide(description: "Clutter types to include; empty unless the sentence asks for them")
    var junkTypes: [RuleJunk]
    @Guide(description: "Document types to include, e.g. receipt and bill for 'bills and receipts'; empty if none")
    var docTypes: [RuleDoc]
    @Guide(description: "Lowercase words to look for in text read from photos, e.g. a shop or app name; empty if none")
    var keywords: [String]
    @Guide(description: "Things that must be visible in the photo, as singular nouns picked from the label list in the instructions, e.g. dog, beach, food; empty if none")
    var labels: [String]
    @Guide(description: "How the photos look, as a short English phrase for picture search, e.g. 'a girl', 'eyeglasses', 'a dog on a beach'; empty for requests about text or documents such as receipts")
    var visual: String
    @Guide(description: "Earliest date as yyyy-MM-dd, or empty")
    var dateFrom: String
    @Guide(description: "Latest date as yyyy-MM-dd, or empty")
    var dateTo: String
}

enum RuleCompilerConfig {
    /// Most frequent labels sent as the vocabulary; keeps the on-device prompt well inside its context.
    static let maxLabels = 200
    static func instructions(today: Date, labels: [String]) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return base + " Today is \(f.string(from: today))." + (labels.isEmpty ? "" : " Labels found in this library: \(labels.joined(separator: ", ")).")
    }
    static let base = """
    Turn the user's sentence into a photo album rule. Use only the listed fields. \
    Use labels for things seen in a photo and keywords only for words written in it. \
    For people (girls, friends, family, selfies) use the label "people"; for glasses or lenses use "eyeglasses". \
    Leave kinds, junk types, document types and dates empty unless the sentence clearly names them; fewer conditions are better. \
    "Photos of my dog at the beach" -> name "Dog at the beach", kinds [camera], labels ["dog", "beach"]. \
    Examples: "Bills and receipts go to Tax 2026" -> name "Tax 2026", docTypes [bill, receipt]. \
    "Swiggy and Zomato orders" -> name "Food orders", keywords ["swiggy", "zomato"]. \
    "Screenshots from March 2026" -> name "March screenshots", kinds [screenshot], dateFrom "2026-03-01", dateTo "2026-03-31".
    """
}

extension HybridJudge {
    /// Turns a sentence into a rule. On-device by default; Gemini only when the user allowed cloud help (`cloudConsent`)
    /// and the caller allows it. Gemini then gets the masked sentence and the library's generic label words, all logged.
    func compileRule(_ sentence: String, labels: [String], allowCloud: Bool = true) async throws -> RuleSpec {
        let instructions = RuleCompilerConfig.instructions(today: Date(), labels: labels)
        let sent = mask(sentence)
        let r = try await respond(to: sent, instructions: instructions, generating: RuleDraft.self,
                                  allowCloud: allowCloud, task: "smart album rule")
        return Self.spec(from: r, vocabulary: labels)
    }

    /// One structured call through Firebase AI Logic. On-device when available; Gemini when on-device isn't
    /// (or as a fallback) and only if the caller allows it and the user consented. Cloud prompts are logged in full.
    func respond<T: Generable>(to prompt: String, instructions: String, generating: T.Type, allowCloud: Bool, task: String) async throws -> T {
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let onDeviceOK = status == .available
        let cloudOK = allowCloud && cloudConsent == true
        guard onDeviceOK || cloudOK else { throw AIUnavailable() }
        let session = !onDeviceOK
            ? ai.generativeModelSession(model: .geminiModel(name: JudgeConfig.cloudModel), instructions: instructions)
            : cloudOK
                ? ai.generativeModelSession(model: .hybridModel(primary: .systemModel(), secondary: .geminiModel(name: JudgeConfig.cloudModel)), instructions: instructions)
                : ai.generativeModelSession(model: .systemModel(), instructions: instructions)
        if !onDeviceOK { cloudBusy = true }
        defer { cloudBusy = false }
        let r = try await session.respond(to: prompt, generating: T.self)
        lastOnDevice = r.rawResponse.modelVersion == JudgeConfig.onDeviceVersion
        if !lastOnDevice {
            logCloud(task: task, model: r.rawResponse.modelVersion, text: "Instructions: \(instructions)\n\nPrompt: \(prompt)")
        }
        return r.content
    }

    nonisolated static func spec(from d: RuleDraft, vocabulary: [String] = []) -> RuleSpec {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let kinds: [Kind] = d.kinds.compactMap { Kind(rawValue: "\($0)") }
        let junk: [JunkType] = d.junkTypes.compactMap { JunkType(rawValue: "\($0)") }
        let docs: [DocType] = d.docTypes.compactMap { DocType(rawValue: "\($0)") }
        let clean = { (a: [String]) in a.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        // A label the library has never seen can't match a photo; search it as written text instead.
        let known = Set(vocabulary.flatMap { $0.lowercased().split(separator: "_").map(String.init) })
        let asked = clean(d.labels)
        let labels = vocabulary.isEmpty ? asked : asked.filter { l in known.contains(l) || known.contains(String(l.dropLast())) }
        var seen = Set<String>()
        let words = (clean(d.keywords) + asked.filter { !labels.contains($0) }).filter { seen.insert($0).inserted }
        var spec = RuleSpec(name: d.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        include: .init(kinds: kinds.isEmpty ? nil : kinds, junkTypes: junk.isEmpty ? nil : junk,
                                       docTypes: docs.isEmpty ? nil : docs, keywords: words.isEmpty ? nil : words,
                                       labels: labels.isEmpty ? nil : labels,
                                       dateFrom: d.dateFrom.isEmpty ? nil : f.date(from: d.dateFrom),
                                       dateTo: d.dateTo.isEmpty ? nil : f.date(from: d.dateTo).map { $0.addingTimeInterval(86_399) }))
        let look = d.visual.trimmingCharacters(in: .whitespacesAndNewlines)
        spec.visual = look.isEmpty ? nil : look
        // Picture-only sentence ("girls"): keep its words so the rule still works when picture search is off.
        if words.isEmpty, labels.isEmpty, docs.isEmpty, !look.isEmpty {
            let filler: Set<String> = ["a", "an", "the", "of", "with", "and", "in", "on", "at", "photo", "photos", "picture", "pictures", "my"]
            spec.include.keywords = look.lowercased().split(separator: " ").map(String.init).filter { !filler.contains($0) }
        }
        return spec
    }
}

/// Neither on-device AI nor (consented) cloud help is available for this request.
struct AIUnavailable: Error {}
