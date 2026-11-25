public struct PlanItem: Sendable, Equatable {
    public var id: String
    public var bytes: Int64
    public var reason: String
    public var tier: Int
}

/// Tier for "Get me X GB", least risky first; nil means never offered by the planner.
func plannerTier(_ v: Verdict, id: String, near: Set<String>, exact: Set<String>) -> Int? {
    if exact.contains(id) { return 1 }
    switch v.junkType {
    case .expiredOTP, .expiredQR: return 2
    case .forward: return 3
    case .screenRecording: return 4
    case .bigVideo: return 5
    case .blurry: return 6
    default: return near.contains(id) ? 7 : nil
    }
}

/// Safest set of local items that reaches the target. Stops as soon as the target is met.
public func planSpace(targetBytes: Int64, items: [(Verdict, PhotoRecord)], nearDuplicateIDs: Set<String>,
                      exactDuplicateIDs: Set<String>) -> (items: [PlanItem], freedBytes: Int64, metTarget: Bool) {
    let candidates = items.compactMap { v, r -> PlanItem? in
        guard r.isLocal, r.fileBytes > 0, !r.isFavorite, v.sensitive == nil,
              !(r.cameraMake != nil && r.faceCount > 0 && !r.isScreenshot && !exactDuplicateIDs.contains(r.id)),
              let tier = plannerTier(v, id: r.id, near: nearDuplicateIDs, exact: exactDuplicateIDs) else { return nil }
        return PlanItem(id: r.id, bytes: r.fileBytes, reason: v.reason, tier: tier)
    }.sorted { ($0.tier, -$0.bytes) < ($1.tier, -$1.bytes) }

    var chosen: [PlanItem] = []
    var freed: Int64 = 0
    for c in candidates where freed < targetBytes {
        chosen.append(c)
        freed += c.bytes
    }
    return (chosen, freed, freed >= targetBytes)
}
