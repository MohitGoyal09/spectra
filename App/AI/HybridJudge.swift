import Foundation
import FoundationModels
import FirebaseAILogic
import TidyCore

// MARK: - Guided generation types (the model fills these; it never returns a verdict)

@Generable enum NoteKind { case camera, screenshot, forward, download, document, recording }
@Generable enum SavedKind { case none, booking, address, event, transit, recipe, order }

@Generable struct PhotoNote {
    @Guide(description: "The id number at the start of the input line")
    var id: Int
    var kind: NoteKind
    @Guide(description: "A 2 to 6 word title for what the photo shows, in your own words. Never copy the line's text.")
    var title: String
    var saved: SavedKind
    @Guide(description: "When saved is not none, the key detail such as a date, place, code or time. Otherwise empty.")
    var detail: String
}

@Generable struct NoteBatch { var notes: [PhotoNote] }

enum JudgeConfig {
    static let instructions = """
    You label phone photos for a storage cleaner. Each input line describes one photo as text only: \
    id | flags | scene labels | rule hits | text read from the image | age. For every line give one note. \
    kind: camera for real camera photos, screenshot, forward for greeting or chain images, download for saved images and memes, \
    document for photos of paper, recording for screen recordings. title: 2 to 6 words in your own words. \
    saved: booking, address, event, transit, recipe or order only when the photo holds that information, else none. \
    Examples: "screenshot | document | | Employee discounts on JBL speakers" -> title "Employee discount notice". \
    "camera-exif | laptop,structure | |" -> title "Laptop on a desk". "whatsapp | flower | greeting | Good morning" -> title "Good morning greeting".
    """
    static let cloudModel = "gemini-3.5-flash-lite"
    static let onDeviceVersion = "apple-foundation-models-system-language-model"
}

enum OnDeviceStatus: Equatable { case available, notEligible, intelligenceOff, modelNotReady, other(String) }

@MainActor protocol Judging {
    func notes(for batch: [(PhotoRecord, RuleHits)]) async -> [ModelNote]
}

/// Firebase AI Logic hybrid judge. On-device first; the cloud gets masked text only, only with consent; sensitive items never reach any model.
@MainActor @Observable final class HybridJudge: Judging {
    private let realStatus: OnDeviceStatus
    /// Demo switch: behave like an iPhone without Apple Intelligence, so the cloud fallback can be shown.
    var simulateNoOnDevice = UserDefaults.standard.bool(forKey: "simulateNoOnDevice") {
        didSet { UserDefaults.standard.set(simulateNoOnDevice, forKey: "simulateNoOnDevice") }
    }
    var status: OnDeviceStatus { simulateNoOnDevice ? .notEligible : realStatus }
    /// Where the most recent structured answer came from (shown as a badge next to it).
    var lastOnDevice = true
    private(set) var onDeviceCalls = 0
    private(set) var cloudCalls = 0
    var cloudBusy = false
    @ObservationIgnored private let log: PrivacyLog
    @ObservationIgnored private lazy var ai = FirebaseAI.firebaseAI(backend: .googleAI())

    var cloudConsent: Bool? = UserDefaults.standard.object(forKey: "cloudConsent") as? Bool {
        didSet { UserDefaults.standard.set(cloudConsent, forKey: "cloudConsent") }
    }
    var needsConsent: Bool { status != .available && cloudConsent == nil }

    init(log: PrivacyLog) {
        self.log = log
        switch FirebaseAI.SystemLanguageModel.default.availability {
        case .available: realStatus = .available
        case .unavailable(.deviceNotEligible): realStatus = .notEligible
        case .unavailable(.appleIntelligenceNotEnabled): realStatus = .intelligenceOff
        case .unavailable(.modelNotReady): realStatus = .modelNotReady
        case .unavailable(let r): realStatus = .other(String(describing: r))
        }
    }

    func notes(for batch: [(PhotoRecord, RuleHits)]) async -> [ModelNote] {
        let safe = batch.filter { $0.1.sensitive == nil }
        guard !safe.isEmpty else { return [] }
        if status == .available {
            if let notes = try? await onDevice(safe) { return notes }
            var out: [ModelNote] = []   // context overflow or other error: retry one photo at a time
            for item in safe {
                if let n = try? await onDevice([item]) { out += n }
                else if cloudConsent == true, let n = try? await cloud([item]) { out += n }
            }
            return out
        }
        guard cloudConsent == true else { return [] }
        return (try? await cloud(safe)) ?? []
    }

    // MARK: - Calls

    private func renumbered(_ batch: [(PhotoRecord, RuleHits)]) -> ([(PhotoRecord, RuleHits)], [String]) {
        var ids: [String] = []
        let items = batch.enumerated().map { i, item -> (PhotoRecord, RuleHits) in
            ids.append(item.0.id)
            var r = item.0
            r.id = String(i + 1)
            return (r, item.1)
        }
        return (items, ids)
    }

    private func onDevice(_ batch: [(PhotoRecord, RuleHits)]) async throws -> [ModelNote] {
        let (items, ids) = renumbered(batch)
        let session = ai.generativeModelSession(model: .systemModel(), instructions: JudgeConfig.instructions)
        let r = try await session.respond(to: judgePrompt(records: items, forCloud: false, now: .now), generating: NoteBatch.self,
                                          options: .foundationModels(FirebaseAI.GenerationOptions(temperature: 0.2, maximumResponseTokens: 400)))
        onDeviceCalls += 1
        return convert(r.content.notes, ids: ids)
    }

    private func cloud(_ batch: [(PhotoRecord, RuleHits)]) async throws -> [ModelNote] {
        let (items, ids) = renumbered(batch)
        let prompt = judgePrompt(records: items, forCloud: true, now: .now)
        guard !prompt.isEmpty else { return [] }
        cloudBusy = true
        defer { cloudBusy = false }
        let session = ai.generativeModelSession(model: .geminiModel(name: JudgeConfig.cloudModel), instructions: JudgeConfig.instructions)
        let r = try await session.respond(to: prompt, generating: NoteBatch.self)
        cloudCalls += 1
        logCloud(task: "photo titles", model: r.rawResponse.modelVersion, text: prompt)
        return convert(r.content.notes, ids: ids)
    }

    func logCloud(task: String, model: String, text: String) {
        log.append(PrivacyEntry(date: .now, task: task, model: model, sentText: text))
    }

    private func convert(_ notes: [PhotoNote], ids: [String]) -> [ModelNote] {
        notes.compactMap { n -> ModelNote? in
            guard n.id >= 1, n.id <= ids.count else { return nil }
            let kind: Kind = switch n.kind {
            case .camera: .camera
            case .screenshot: .screenshot
            case .forward: .forward
            case .download: .download
            case .document: .document
            case .recording: .recording
            }
            let saved: SavedInfo? = n.saved == .none ? nil : SavedInfo(type: "\(n.saved)", title: n.title, fields: n.detail.isEmpty ? [:] : ["detail": n.detail])
            return ModelNote(id: ids[n.id - 1], kind: kind, title: n.title, savedInfo: saved)
        }
    }
}
