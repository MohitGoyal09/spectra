import SwiftUI
import UserNotifications

/// A card to share after a cleanup: how much was freed, and that no photo was uploaded. Rendered to an image.
struct FreedCard: View {
    let freedBytes: Int64
    let items: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Spectra", systemImage: "sparkles").font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: Palette.glow, startPoint: .leading, endPoint: .trailing))
            Spacer()
            Text("Freed \(gbText(freedBytes))").font(.system(size: 64, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
            Text("\(items) photos and videos cleaned up on my iPhone.").font(.system(size: 22, weight: .medium)).foregroundStyle(.white.opacity(0.8))
            Label("0 photos uploaded · sorted by on-device AI", systemImage: "lock.iphone").font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .padding(44)
        .frame(width: 1080 / 2, height: 1080 / 2, alignment: .leading)
        .background(
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.08)
                RadialGradient(colors: [Palette.glow[1].opacity(0.55), .clear], center: .topTrailing, startRadius: 0, endRadius: 420)
                RadialGradient(colors: [Palette.glow[0].opacity(0.45), .clear], center: .bottomLeading, startRadius: 0, endRadius: 380)
            }
        )
    }

    /// 1080 × 1080 PNG for Messages, WhatsApp or Instagram.
    @MainActor static func image(freedBytes: Int64, items: Int) -> Image? {
        let r = ImageRenderer(content: FreedCard(freedBytes: freedBytes, items: items))
        r.scale = 2
        return r.uiImage.map(Image.init(uiImage:))
    }
}

/// Weekly reminder with this week's numbers, scheduled for Sunday 10:00 and refreshed whenever the numbers change.
enum WeeklyDigest {
    private static let id = "weeklyDigest"
    private static let enabledKey = "weeklyDigestOn"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Asks permission the first time; returns whether the digest is on.
    static func setOn(_ on: Bool, summary: WidgetSummary) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard on else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            center.removePendingNotificationRequests(withIdentifiers: [id]); return false
        }
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge])) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        if granted { schedule(summary) }
        return granted
    }

    static func schedule(_ s: WidgetSummary) {
        guard isOn else { return }
        let content = UNMutableNotificationContent()
        content.title = s.freeableBytes > 0 ? "\(gbText(s.freeableBytes)) can go" : "Your photos are tidy"
        var parts: [String] = []
        if s.expiredScreenshots > 0 { parts.append("\(s.expiredScreenshots) expired screenshots") }
        if s.duplicates > 0 { parts.append("\(s.duplicates) copies") }
        if s.forwards > 0 { parts.append("\(s.forwards) forwards") }
        content.body = parts.isEmpty ? "Nothing to clean this week." : parts.joined(separator: " · ") + ". Review in a minute; nothing goes without you."
        content.targetContentIdentifier = "cleanup"
        var when = DateComponents(); when.weekday = 1; when.hour = 10
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content,
                                                                     trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
    }
}

/// Opens Clean Up when the weekly digest is tapped.
final class DigestTapHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {   // no stored state
    static let shared = DigestTapHandler()
    /// Film mode only: show the clean-as-you-go banner while Spectra is open, so the film never shows the user's own
    /// home or lock screen. Normal builds keep iOS's default (no banner while the app is in front).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        FilmScope.isOn ? [.banner, .sound] : []
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let photo = response.notification.request.content.userInfo["photoID"] as? String
        await MainActor.run {
            if let photo { AppModel.current?.pendingViewer = ViewerContext(ids: [photo], start: 0) }   // clean as you go
            else { AppModel.current?.tab = .cleanUp }                                                  // weekly digest
        }
    }
}
