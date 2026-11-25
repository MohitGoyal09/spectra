public struct ICloudPlan: Codable, Sendable, Equatable {
    public var gb: Int
    public var inrPerMonth: Int
    public init(gb: Int, inrPerMonth: Int) { self.gb = gb; self.inrPerMonth = inrPerMonth }
    /// Defaults until Remote Config `icloud_plans_inr` overrides them; verify current prices.
    public static let indiaDefaults = [ICloudPlan(gb: 50, inrPerMonth: 75), ICloudPlan(gb: 200, inrPerMonth: 219), ICloudPlan(gb: 2048, inrPerMonth: 749)]
}

/// The plan the user needs now and the cheaper one that fits after cleanup; nil if the tier does not change.
public func cheaperPlanSaving(usedBytes: Int64, freedBytes: Int64, plans: [ICloudPlan]) -> (from: ICloudPlan, to: ICloudPlan)? {
    let sorted = plans.sorted { $0.gb < $1.gb }
    func fit(_ bytes: Int64) -> ICloudPlan? { sorted.first { Int64($0.gb) * 1_000_000_000 >= bytes } }
    guard let from = fit(usedBytes), let to = fit(max(0, usedBytes - freedBytes)), to.gb < from.gb else { return nil }
    return (from, to)
}
