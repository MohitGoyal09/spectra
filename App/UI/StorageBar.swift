import SwiftUI
import TidyCore

/// Your photo library on this iPhone, split by collection in its own colour (like Settings › iPhone Storage),
/// with what can safely go called out above it.
struct StorageBar: View {
    let storage: StorageSnapshot
    let segments: [(bucket: Bucket, bytes: Int64)]
    let freeable: Int64
    var review: Int64 = 0
    private static let minSegment: CGFloat = 3
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var total: Int64 { max(segments.map(\.bytes).reduce(0, +), 1) }

    private var headline: some View {
        Text(freeable > 0 ? "\(gbText(freeable)) can go" : segments.isEmpty ? "Scan to see what can go" : "Nothing to clear")
            .font(.title3.weight(.semibold)).contentTransition(.numericText())
    }
    private var capacity: some View {
        Text("Photos \(gbText(total)) · \(gbText(storage.available)) free").font(.footnote).foregroundStyle(Palette.secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { headline; Spacer(); capacity.fixedSize() }
                VStack(alignment: .leading, spacing: 2) { headline; capacity }
            }
            if review > 0 {
                Text("Plus \(gbText(review)) worth a look").font(.subheadline).foregroundStyle(Palette.secondary)
            }
            GeometryReader { g in
                let widths = layout(g.size.width)
                HStack(spacing: 1.5) {
                    ForEach(Array(segments.enumerated()), id: \.element.bucket) { i, s in
                        Rectangle().fill(s.bucket.tint).frame(width: grown || reduceMotion ? widths[i] : 0)
                            .animation(Motion.smooth.delay(Double(i) * 0.05), value: grown)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.fill)
                .clipShape(Capsule())
            }
            .frame(height: 12)
            legend
        }
        .padding(Space.l)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .animation(Motion.smooth, value: freeable)
        .onAppear { grown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gbText(freeable)) can be freed safely. Photos use \(gbText(total)); \(gbText(storage.available)) free on this iPhone.")
    }

    /// Proportional widths with a visible minimum so small collections still show their colour.
    private func layout(_ width: CGFloat) -> [CGFloat] {
        let gaps = CGFloat(max(segments.count - 1, 0)) * 1.5
        let usable = max(width - gaps, 0)
        let raw = segments.map { usable * CGFloat(Double($0.bytes) / Double(total)) }
        let bumped = raw.map { max($0, Self.minSegment) }
        let excess = bumped.reduce(0, +) - usable
        guard excess > 0, let big = raw.indices.max(by: { raw[$0] < raw[$1] }) else { return bumped }
        var out = bumped; out[big] = max(out[big] - excess, Self.minSegment)
        return out
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(segments.prefix(6), id: \.bucket) { s in
                HStack(spacing: 6) {
                    Circle().fill(s.bucket.tint).frame(width: 8, height: 8)
                    Text(s.bucket.title).font(.caption).foregroundStyle(Palette.label).lineLimit(1)
                    Text(gbText(s.bytes)).font(.caption).foregroundStyle(Palette.secondary).monospacedDigit()
                }
            }
        }
    }
}
