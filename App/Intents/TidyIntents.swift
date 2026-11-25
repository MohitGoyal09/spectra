import AppIntents
import TidyCore

/// "Hey Siri, free up 2 GB with Spectra": opens Clean Up's planner with that target. Nothing is deleted without the user.
struct FreeUpSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Free Up Space"
    static let description = IntentDescription("Opens Spectra's planner with a space target. You review before anything is deleted.")
    static let openAppWhenRun = true

    @Parameter(title: "Gigabytes", default: 1, inclusiveRange: (0.5, 50))
    var gigabytes: Double

    @MainActor func perform() async throws -> some IntentResult {
        AppModel.current?.openPlanner(gigabytes: gigabytes)
        return .result()
    }
}

/// "Ask Spectra what's my Wi-Fi password": answered on this iPhone from text in your photos.
struct AskPhotosIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Your Photos"
    static let description = IntentDescription("Answers a question from text in your photos, on this iPhone. Photo text never goes to the cloud.")
    /// Photo-derived answers never play on a locked iPhone.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Question", requestValueDialog: "What do you want to know?")
    var question: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let model = AppModel.current, model.hasIndex else {
            return .result(value: "", dialog: "Open Spectra and scan your photos first.")
        }
        let r = try? await model.judge.ask(question, items: model.snapshot.all)
        let answer = r?.answer ?? "I couldn't find that in your photos."
        return .result(value: answer, dialog: "\(answer)")
    }
}

/// "How much can Spectra free?"
struct StorageSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "How Much Can I Free?"
    static let description = IntentDescription("Says how much space Spectra can free safely, and how much is worth a look.")
    /// Photo-derived answers never play on a locked iPhone.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = AppModel.current, model.hasIndex else { return .result(dialog: "Open Spectra and scan your photos first.") }
        return .result(dialog: "\(gbText(model.freeableBytes)) can go safely, and \(gbText(model.reviewBytes)) more is worth a look.")
    }
}

struct TidyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FreeUpSpaceIntent(), phrases: ["Free up space with \(.applicationName)", "Clean my photos with \(.applicationName)"],
                    shortTitle: "Free Up Space", systemImageName: "sparkles")
        AppShortcut(intent: AskPhotosIntent(), phrases: ["Ask \(.applicationName)", "Ask my photos in \(.applicationName)"],
                    shortTitle: "Ask Your Photos", systemImageName: "questionmark.bubble")
        AppShortcut(intent: StorageSummaryIntent(), phrases: ["How much can \(.applicationName) free", "\(.applicationName) storage"],
                    shortTitle: "How Much Can I Free?", systemImageName: "internaldrive")
    }
}
