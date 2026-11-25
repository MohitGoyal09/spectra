import SwiftUI
import TidyCore

/// Apple Photos collection card: a 2×2 cover of the collection's own photos, title, count and size.
struct CollectionCard: View {
    let bucket: Bucket
    let coverIDs: [String]
    let count: Int
    let bytes: Int64
    var glow: GlowState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow { cell(0); cell(1) }
                GridRow { cell(2); cell(3) }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                if bucket == .idsCards {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(.ultraThinMaterial)
                    Image(systemName: "lock.fill").font(.title).foregroundStyle(Palette.locked)
                }
            }
            .glowBorder(glow, cornerRadius: Radius.card)
            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.label)
                Text("\(count.formatted()) · \(gbText(bytes))").font(.footnote).foregroundStyle(Palette.secondary).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bucket.title), \(count) items, \(gbText(bytes))")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private func cell(_ i: Int) -> some View {
        if i < coverIDs.count {
            Color.clear.aspectRatio(1, contentMode: .fit).overlay(AssetThumbnail(id: coverIDs[i], side: 90)).clipped()
        } else {
            Palette.fill.aspectRatio(1, contentMode: .fit)
        }
    }
}
