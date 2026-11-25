import WidgetKit
import SwiftUI

struct SummaryEntry: TimelineEntry { let date: Date; let summary: WidgetSummary? }

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: .now, summary: WidgetSummary(freeableBytes: 1_400_000_000, reviewBytes: 3_100_000_000, expiredScreenshots: 41, duplicates: 74, forwards: 12))
    }
    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        completion(Timeline(entries: [SummaryEntry(date: .now, summary: WidgetSummary.load())], policy: .after(.now.addingTimeInterval(6 * 3600))))
    }
}

/// "1.4 GB can go": the space TidyRoll can free safely, and what makes it up. Tap opens Clean Up.
struct TidyWidgetView: View {
    let entry: SummaryEntry
    @Environment(\.widgetFamily) private var family
    private static let glow: [Color] = [Color(red: 0.36, green: 0.55, blue: 1.0), Color(red: 0.70, green: 0.42, blue: 1.0), Color(red: 1.0, green: 0.45, blue: 0.55)]

    var body: some View {
        Group {
            if let s = entry.summary {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Spectra", systemImage: "sparkles").font(.caption2.weight(.semibold))
                        .foregroundStyle(LinearGradient(colors: Self.glow, startPoint: .leading, endPoint: .trailing))
                    Spacer(minLength: 0)
                    Text(ByteCountFormatter.string(fromByteCount: s.freeableBytes, countStyle: .file))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
                    Text("can go safely").font(.footnote).foregroundStyle(.secondary)
                    if family != .systemSmall {
                        HStack(spacing: 14) {
                            stat(s.duplicates, "copies", "square.on.square")
                            stat(s.expiredScreenshots, "expired", "clock.badge.xmark")
                            stat(s.forwards, "forwards", "arrowshape.turn.up.right")
                        }
                        .padding(.top, 2)
                    } else if s.expiredScreenshots > 0 {
                        Text("\(s.expiredScreenshots) expired screenshots").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(LinearGradient(colors: Self.glow, startPoint: .leading, endPoint: .trailing))
                    Text("Scan your photos in Spectra").font(.footnote.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "tidyroll://cleanup"))
    }

    private func stat(_ n: Int, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("\(n)", systemImage: symbol).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

@main
struct TidyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TidyWidget", provider: SummaryProvider()) { TidyWidgetView(entry: $0) }
            .configurationDisplayName("Space to free")
            .description("How much Spectra can free safely. Tap to clean up.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
