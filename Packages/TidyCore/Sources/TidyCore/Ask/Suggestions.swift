import Foundation

public struct AlbumSuggestion: Sendable, Equatable {
    public var spec: RuleSpec
    public var ids: [String]          // newest first
}

/// Vision labels too broad to make a good album on their own.
let genericLabels: Set<String> = [
    "people", "adult", "child", "structure", "outdoor", "indoor", "sky", "document", "screenshot", "text", "printed_page",
    "machine", "consumer_electronics", "clothing", "material", "conveyance", "sign", "light", "land", "wood_processed",
    "furniture", "interior_room", "housewares", "container", "tool", "art", "paper", "liquid", "water", "cloudy", "blue_sky",
    "optical_equipment", "eyeglasses", "portal", "textile", "dial", "jewelry", "headgear", "hat", "shoes", "footwear",
]

/// Albums worth suggesting from what's already in the library: frequent subjects in camera photos (dog, beach, food)
/// and documents (receipts and bills, tickets and bookings). Skips IDs, generic labels and rules the user already has.
public func suggestAlbums(_ items: [(verdict: Verdict, record: PhotoRecord)], existing: [RuleSpec],
                          minCount: Int = 6, limit: Int = 6) -> [AlbumSuggestion] {
    let safe = items.filter { $0.verdict.sensitive == nil }
    var labelCount: [String: Int] = [:]
    for i in safe where i.verdict.kind == .camera {
        for l in Set(i.record.labels) where !genericLabels.contains(l) { labelCount[l, default: 0] += 1 }
    }
    var specs = labelCount.filter { $0.value >= minCount }.sorted { $0.value > $1.value }.map { l, _ in
        RuleSpec(name: l.replacingOccurrences(of: "_", with: " ").capitalized, include: .init(kinds: [.camera], labels: [l]))
    }
    specs += [
        RuleSpec(name: "Receipts & bills", include: .init(docTypes: [.receipt, .bill])),
        RuleSpec(name: "Tickets & bookings", include: .init(docTypes: [.ticket, .booking])),
    ]
    let taken = existing.map(\.include)
    return specs.filter { !taken.contains($0.include) }
        .map { spec in
            AlbumSuggestion(spec: spec, ids: safe.filter { matches(spec, verdict: $0.verdict, record: $0.record) }
                .sorted { $0.record.createdAt > $1.record.createdAt }.map(\.record.id))
        }
        .filter { $0.ids.count >= ($0.spec.include.docTypes == nil ? minCount : 3) }
        .sorted { $0.ids.count > $1.ids.count }
        .prefix(limit).map { $0 }
}
