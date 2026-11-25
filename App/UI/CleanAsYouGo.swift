import Foundation
import UserNotifications
import TidyCore

/// Clean as you go: a nudge when a screenshot stops being useful. An OTP screenshot a day after it was taken,
/// a ticket the day after its date. Tapping opens that photo, ready to delete. Nothing is deleted without the user.
enum CleanAsYouGo {
    private static let key = "cleanAsYouGoOn"
    private static let prefix = "expiry-"
    private static let maxPending = 30          // iOS keeps at most 64 pending notifications per app
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    struct Reminder: Equatable { let id: String; let fireAt: Date; let title: String; let body: String }

    /// Which reminders are due for these items (pure, so it can be tested).
    static func reminders(_ items: [IndexedItem], now: Date = .now) -> [Reminder] {
        let f = DateFormatter(); f.dateFormat = "d MMM"; f.locale = Locale(identifier: "en_IN")
        let t = DateFormatter(); t.timeStyle = .short
        var out: [Reminder] = []
        for i in items where i.record.isScreenshot && i.verdict.sensitive == nil && i.userKept != true {
            let hits = scanText(i.record.ocrText, barcodes: i.record.barcodePayloads)
            if hits.otp {
                let at = i.record.createdAt.addingTimeInterval(RuleConfig.otpExpiryDays * 86_400)
                if at > now { out.append(Reminder(id: i.record.id, fireAt: at, title: "That OTP has expired",
                                                  body: "Your OTP screenshot from \(t.string(from: i.record.createdAt)) is no use now. Tap to delete it.")) }
            } else if let d = hits.eventDate {
                let at = d.addingTimeInterval(86_400)
                if at > now { out.append(Reminder(id: i.record.id, fireAt: at, title: "Your ticket's date has passed",
                                                  body: "The ticket for \(f.string(from: d)) is done. Tap to delete the screenshot.")) }
            }
        }
        return Array(out.sorted { $0.fireAt < $1.fireAt }.prefix(maxPending))
    }

    /// Asks permission the first time; returns whether alerts are on.
    static func setOn(_ on: Bool, items: [IndexedItem]) async -> Bool {
        guard on else { UserDefaults.standard.set(false, forKey: key); await clear(); return false }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        UserDefaults.standard.set(granted, forKey: key)
        if granted { await schedule(items) }
        return granted
    }

    /// Replaces all pending expiry reminders with the current set.
    static func schedule(_ items: [IndexedItem]) async {
        guard isOn else { return }
        await clear()
        for r in reminders(items) {
            let c = UNMutableNotificationContent()
            c.title = r.title; c.body = r.body; c.userInfo = ["photoID": r.id]
            // Film mode: fire 10 s after scheduling, so the reminder can be filmed on the lock screen.
            let wait = FilmScope.isOn ? 10 : max(60, r.fireAt.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: prefix + r.id, content: c, trigger: trigger))
        }
    }

    private static func clear() async {
        let ids = await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
