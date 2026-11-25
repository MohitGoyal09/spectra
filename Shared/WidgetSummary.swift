import Foundation

/// What the home-screen widget shows, written by the app into the shared App Group after scans and cleanups.
struct WidgetSummary: Codable, Equatable {
    var freeableBytes: Int64 = 0
    var reviewBytes: Int64 = 0
    var expiredScreenshots = 0
    var duplicates = 0
    var forwards = 0
    var updated = Date.distantPast

    static let appGroup = "group.com.mohitgoyal.tidyroll"
    private static let key = "widgetSummary"

    static func load() -> WidgetSummary? {
        UserDefaults(suiteName: appGroup)?.data(forKey: key).flatMap { try? JSONDecoder().decode(WidgetSummary.self, from: $0) }
    }
    func save() { UserDefaults(suiteName: Self.appGroup)?.set(try? JSONEncoder().encode(self), forKey: Self.key) }
}
