import Foundation
import Testing
@testable import TidyCore

private func item(_ id: String, _ junk: JunkType?, _ verdict: VerdictKind, mb: Int64, local: Bool = true,
                  edit: (inout PhotoRecord) -> Void = { _ in }) -> (Verdict, PhotoRecord) {
    var r = PhotoRecord(id: id, createdAt: .now)
    r.fileBytes = mb * 1_000_000
    r.isLocal = local
    edit(&r)
    return (Verdict(id: id, kind: .screenshot, verdict: verdict, reason: "r", junkType: junk, confidence: 0.9, source: .rules), r)
}

@Test func stopsWhenTargetMet() {
    let items = [item("a", .expiredOTP, .junk, mb: 600), item("b", .forward, .junk, mb: 600), item("c", .forward, .junk, mb: 600)]
    let p = planSpace(targetBytes: 1_000_000_000, items: items, nearDuplicateIDs: [], exactDuplicateIDs: [])
    #expect(p.metTarget && p.items.count == 2 && p.freedBytes == 1_200_000_000)
}
@Test func ordersTiersLeastRiskyFirst() {
    let items = [item("blur", .blurry, .review, mb: 900), item("fwd", .forward, .junk, mb: 10),
                 item("dup", nil, .junk, mb: 10), item("otp", .expiredOTP, .junk, mb: 10), item("rec", .screenRecording, .review, mb: 10)]
    let p = planSpace(targetBytes: 10_000_000_000, items: items, nearDuplicateIDs: [], exactDuplicateIDs: ["dup"])
    #expect(p.items.map(\.id) == ["dup", "otp", "fwd", "rec", "blur"])
}
@Test func largestFirstWithinTier() {
    let items = [item("s", .forward, .junk, mb: 5), item("l", .forward, .junk, mb: 50)]
    #expect(planSpace(targetBytes: 1, items: items, nearDuplicateIDs: [], exactDuplicateIDs: []).items.map(\.id) == ["l"])
}
@Test func skipsNonLocalBytes() {
    let items = [item("cloud", .forward, .junk, mb: 900, local: false), item("here", .forward, .junk, mb: 100)]
    let p = planSpace(targetBytes: 50_000_000, items: items, nearDuplicateIDs: [], exactDuplicateIDs: [])
    #expect(p.items.map(\.id) == ["here"])
}
@Test func neverIncludesSensitiveOrFavourite() {
    var sens = item("id", .forward, .junk, mb: 100)
    sens.0.sensitive = .pan
    let fav = item("fav", .forward, .junk, mb: 100) { $0.isFavorite = true }
    let p = planSpace(targetBytes: 10_000_000_000, items: [sens, fav], nearDuplicateIDs: ["id", "fav"], exactDuplicateIDs: [])
    #expect(p.items.isEmpty && !p.metTarget)
}
@Test func reportsUnmetTarget() {
    let p = planSpace(targetBytes: 5_000_000_000, items: [item("a", .forward, .junk, mb: 100)], nearDuplicateIDs: [], exactDuplicateIDs: [])
    #expect(!p.metTarget && p.freedBytes == 100_000_000)
}
@Test func cheaperPlanOnlyWhenBelowTier() {
    let plans = ICloudPlan.indiaDefaults
    let s = cheaperPlanSaving(usedBytes: 60_000_000_000, freedBytes: 15_000_000_000, plans: plans)
    #expect(s?.from.gb == 200 && s?.to.gb == 50)
    #expect(cheaperPlanSaving(usedBytes: 60_000_000_000, freedBytes: 1_000_000_000, plans: plans) == nil)
}
