import SwiftUI
import EventKit
import EventKitUI
import FoundationModels
import FirebaseAILogic
import TidyCore

@Generable struct EventDraft {
    @Guide(description: "A short event title, e.g. 'Flight to Goa' or 'Coldplay concert'")
    var title: String
    @Guide(description: "Start as yyyy-MM-dd HH:mm in 24-hour time, or yyyy-MM-dd when there is no time; empty if no date")
    var start: String
    @Guide(description: "Venue, address or route; empty if none")
    var place: String
}

enum EventConfig {
    static let instructions = """
    Read text from a ticket or booking screenshot and fill in the event. Use only what the text says; never invent a date. \
    For travel, the title names the destination, e.g. "Train to Jaipur".
    """
    static let textChars = 1200
}

extension HybridJudge {
    /// Ticket or booking → calendar event, on this iPhone only (booking text holds names and PNRs).
    func eventDraft(text: String, today: Date = .now) async throws -> EventDraft {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return try await respond(to: "Today is \(f.string(from: today)).\n\n" + String(text.prefix(EventConfig.textChars)),
                                 instructions: EventConfig.instructions, generating: EventDraft.self, allowCloud: false, task: "calendar event")
    }

    nonisolated static func startDate(_ s: String) -> (Date, allDay: Bool)? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"; if let d = f.date(from: s) { return (d, false) }
        f.dateFormat = "yyyy-MM-dd"; if let d = f.date(from: s) { return (d, true) }
        return nil
    }
}

/// Apple's event editor, pre-filled. The user checks it and taps Add; TidyRoll never writes to the calendar itself.
struct EventEditor: UIViewControllerRepresentable {
    let draft: EventDraft
    let note: String
    @Environment(\.dismiss) private var dismiss
    private static let store = EKEventStore()

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let event = EKEvent(eventStore: Self.store)
        event.title = draft.title
        event.location = draft.place.isEmpty ? nil : draft.place
        event.notes = note
        if let (start, allDay) = HybridJudge.startDate(draft.start) {
            event.startDate = start; event.isAllDay = allDay
            event.endDate = allDay ? start : start.addingTimeInterval(3600)
        }
        let vc = EKEventEditViewController()
        vc.eventStore = Self.store
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { dismiss() }
    }
}

extension IndexedItem {
    /// Tickets, bookings, events and travel: worth offering "Add to Calendar".
    var looksLikeEvent: Bool {
        verdict.sensitive == nil && (verdict.docType == .ticket || verdict.docType == .booking
            || ["booking", "event", "transit"].contains(verdict.savedInfo?.type ?? ""))
    }
}

struct EventSheet: Identifiable { let id = UUID(); let draft: EventDraft; let note: String }

extension AppModel {
    /// Reads the photo's text on this iPhone and returns a pre-filled event, or nil with a reason.
    func calendarEvent(for id: String) async -> Result<EventSheet, CalendarError> {
        guard let item = store.items[id], item.verdict.sensitive == nil, !item.record.ocrText.isEmpty else { return .failure(.noText) }
        guard judge.status == .available else { return .failure(.needsOnDevice) }
        guard let d = try? await judge.eventDraft(text: item.record.ocrText) else { return .failure(.notUnderstood) }
        return .success(EventSheet(draft: d, note: "Added by Spectra from a screenshot"))
    }
}

enum CalendarError: Error {
    case noText, needsOnDevice, notUnderstood
    var message: String {
        switch self {
        case .noText: "No text found in this photo"
        case .needsOnDevice: "Needs on-device AI; booking text never goes to the cloud"
        case .notUnderstood: "Couldn't read an event from this photo"
        }
    }
}
