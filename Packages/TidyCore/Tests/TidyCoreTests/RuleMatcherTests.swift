import Foundation
import Testing
@testable import TidyCore

private func pair(_ edit: (inout Verdict, inout PhotoRecord) -> Void) -> (Verdict, PhotoRecord) {
    var v = Verdict(id: "x", kind: .screenshot, verdict: .review, reason: "r", confidence: 0.9, source: .rules)
    var r = PhotoRecord(id: "x", createdAt: ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!)
    edit(&v, &r)
    return (v, r)
}

@Test func billsAndReceiptsRule() {
    let rule = RuleSpec(name: "Tax 2026", include: .init(docTypes: [.bill, .receipt]))
    let (v, r) = pair { v, _ in v.docType = .receipt }
    #expect(matches(rule, verdict: v, record: r))
    let (v2, r2) = pair { v, _ in v.docType = .ticket }
    #expect(!matches(rule, verdict: v2, record: r2))
}
@Test func keywordMatchesOCR() {
    let rule = RuleSpec(name: "Croma", include: .init(keywords: ["croma"]))
    let (v, r) = pair { _, r in r.ocrText = "CROMA Retail invoice" }
    #expect(matches(rule, verdict: v, record: r))
}
@Test func allIncludeFieldsMustMatch() {
    let rule = RuleSpec(name: "x", include: .init(kinds: [.screenshot], docTypes: [.receipt]))
    let (v, r) = pair { v, _ in v.docType = .bill }
    #expect(!matches(rule, verdict: v, record: r))
}
@Test func excludeWins() {
    let rule = RuleSpec(name: "x", include: .init(kinds: [.screenshot]), exclude: .init(keywords: ["swiggy"]))
    let (v, r) = pair { _, r in r.ocrText = "Swiggy order" }
    #expect(!matches(rule, verdict: v, record: r))
}
@Test func dateRange() {
    let f = ISO8601DateFormatter()
    let rule = RuleSpec(name: "x", include: .init(dateFrom: f.date(from: "2026-01-01T00:00:00Z"), dateTo: f.date(from: "2026-03-31T00:00:00Z")))
    let (v, r) = pair { _, _ in }
    #expect(!matches(rule, verdict: v, record: r))
}
@Test func sensitiveNeverMatches() {
    let rule = RuleSpec(name: "x", include: .init(kinds: [.screenshot]))
    let (v, r) = pair { v, _ in v.sensitive = .pan }
    #expect(!matches(rule, verdict: v, record: r))
}
@Test func emptyIncludeMatchesNothing() {
    let (v, r) = pair { _, _ in }
    #expect(!matches(RuleSpec(name: "x", include: .init()), verdict: v, record: r))
}
@Test func decodesCloudRuleJSON() throws {
    let json = #"{"name":"Tax 2026","include":{"doc_types":["bill","receipt"],"keywords":["invoice"]},"exclude":{"junk_types":["expired_otp"]}}"#
    let rule = try JSONDecoder().decode(RuleSpec.self, from: Data(json.utf8))
    #expect(rule.include.docTypes == [.bill, .receipt] && rule.exclude?.junkTypes == [.expiredOTP])
}
@Test func labelMatchesVisualContent() {
    let rule = RuleSpec(name: "Dogs", include: .init(labels: ["dogs"]))
    let (v, r) = pair { _, r in r.labels = ["animal", "dog"] }
    #expect(matches(rule, verdict: v, record: r))
    let (v2, r2) = pair { _, r in r.labels = ["cat"] }
    #expect(!matches(rule, verdict: v2, record: r2))
}
@Test func labelIgnoresUnderscores() {
    let rule = RuleSpec(name: "Sunsets", include: .init(labels: ["sunset"]))
    let (v, r) = pair { _, r in r.labels = ["sunset_sunrise"] }
    #expect(matches(rule, verdict: v, record: r))
}
@Test func searchNeedsEveryWordInAnyOrder() {
    #expect(searchMatches("dog beach", in: "outdoor beach sand dog"))
    #expect(searchMatches("Receipts", in: "swiggy receipt"))
    #expect(!searchMatches("dog cat", in: "dog park"))
    #expect(!searchMatches("", in: "anything"))
}
@Test func searchMatchesWholeWordsNotFragments() {
    #expect(!searchMatches("lens", in: "challenges and excellence"))
    #expect(searchMatches("lens", in: "lenskart store"))
    #expect(searchMatches("receipts", in: "swiggy receipt"))
}
@Test func everydayWordsReachVisionLabels() {
    #expect(searchMatches("girls", in: "camera photo people adult"))
    #expect(searchMatches("glasses", in: "optical equipment eyeglasses"))
    let lens = RuleSpec(name: "Lens", include: .init(keywords: ["lens"]))
    let (v, r) = pair { _, r in r.labels = ["eyeglasses"] }
    #expect(matches(lens, verdict: v, record: r), "a keyword also finds photos that show it")
    let (v2, r2) = pair { _, r in r.ocrText = "challenges" }
    #expect(!matches(lens, verdict: v2, record: r2))
    let girls = RuleSpec(name: "Girls", include: .init(kinds: [.screenshot], labels: ["girls"]))
    let (v3, r3) = pair { _, r in r.labels = ["people", "adult"] }
    #expect(matches(girls, verdict: v3, record: r3))
}
@Test func weakLabelsDoNotMatch() {
    let rule = RuleSpec(name: "Dogs", include: .init(labels: ["dog"]))
    let (v, r) = pair { _, r in r.labelScores = ["dog": 0.12, "cat": 0.8] }
    #expect(!matches(rule, verdict: v, record: r))
    let (v2, r2) = pair { _, r in r.labelScores = ["dog": 0.6] }
    #expect(matches(rule, verdict: v2, record: r2))
}
@Test func placeNamesMatchKeywords() {
    let rule = RuleSpec(name: "Goa", include: .init(keywords: ["goa"]))
    let (v, r) = pair { _, r in r.place = "Panaji, Goa, India" }
    #expect(matches(rule, verdict: v, record: r))
}
@Test func visualRuleNeedsPictureOrTextAndKeepsStructure() {
    var rule = RuleSpec(name: "Lens", include: .init(kinds: [.screenshot], keywords: ["lens"], labels: ["eyeglasses"]))
    rule.visual = "eyeglasses"
    let (v, r) = pair { _, r in r.labels = ["eyeglasses"] }
    #expect(!matches(rule, verdict: v, record: r, visual: false), "with picture search on, labels give way to it")
    #expect(matches(rule, verdict: v, record: r, visual: true))
    let (v2, r2) = pair { _, r in r.ocrText = "Lenskart" }
    #expect(matches(rule, verdict: v2, record: r2, visual: false), "written words still count")
    let (v3, r3) = pair { v, _ in v.kind = .camera }
    #expect(!matches(rule, verdict: v3, record: r3, visual: true), "kind still has to hold")
    #expect(matches(rule, verdict: v, record: r), "without picture search the labels decide")
}
@Test func searchRanksStrongMatchesFirst() {
    let strong = searchScore("dog", text: "camera photo", labelScores: ["dog": 0.9])
    let weak = searchScore("dog", text: "camera photo", labelScores: ["dog": 0.3])
    let text = searchScore("dog", text: "hot dog stall", labelScores: [:])
    #expect(strong! > weak!)
    #expect(text == 1)
    #expect(searchScore("dog cat", text: "dog", labelScores: [:]) == nil)
}
@Test func clipPickKeepsOnlyStandouts() {
    var sims = [Float](repeating: 0.18, count: 200)
    sims[7] = 0.31; sims[42] = 0.29; sims[3] = 0.2
    #expect(clipPick(sims) == [7, 42])
    #expect(clipPick([Float](repeating: 0.15, count: 50)).isEmpty, "nothing stands out, nothing returned")
}
@Test func shortWordsMatchWholeWordsOnly() {
    #expect(!searchMatches("red", in: "build redis in rust"), "'red' is not 'redis'")
    #expect(searchMatches("red", in: "a red car"))
    #expect(searchMatches("lens", in: "lenskart"), "longer words still match word starts")
}
