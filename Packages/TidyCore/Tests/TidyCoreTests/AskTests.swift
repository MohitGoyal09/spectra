import Foundation
import Testing
@testable import TidyCore

private let d0 = Date(timeIntervalSince1970: 1_780_000_000)

@Test func detectsQuestions() {
    #expect(isQuestion("What's my wifi password"))
    #expect(isQuestion("when is my flight to goa?"))
    #expect(isQuestion("swiggy bills?"))
    #expect(!isQuestion("dog at the beach"))
}
@Test func retrieveRanksRareWordsFirst() {
    let docs = [(id: "a", text: "Wi-Fi network CafeBlue password: tea4two"),
                (id: "b", text: "Your order from Swiggy"),
                (id: "c", text: "Network settings")]
    #expect(retrieve("what is my wifi password", from: docs, limit: 2).first == "a")
    #expect(retrieve("swiggy order", from: docs, limit: 3).first == "b")
    #expect(retrieve("what is my", from: docs, limit: 3).isEmpty, "stop words alone retrieve nothing")
}

private func item(_ id: String, kind: Kind = .camera, labels: [String] = [], doc: DocType? = nil, sensitive: Sensitive? = nil) -> (verdict: Verdict, record: PhotoRecord) {
    var v = Verdict(id: id, kind: kind, verdict: .keep, reason: "r", confidence: 1, source: .rules)
    v.docType = doc; v.sensitive = sensitive
    var r = PhotoRecord(id: id, createdAt: d0); r.labels = labels
    return (v, r)
}

@Test func suggestsFrequentSubjects() {
    let items = (0..<8).map { item("d\($0)", labels: ["dog", "people"]) } + (0..<3).map { item("c\($0)", labels: ["cat"]) }
    let s = suggestAlbums(items, existing: [], minCount: 6)
    #expect(s.map(\.spec.include.labels) == [["dog"]], "generic labels and rare subjects are skipped")
    #expect(s.first?.ids.count == 8)
}
@Test func suggestsReceiptsAndSkipsExisting() {
    let items = (0..<4).map { item("r\($0)", kind: .screenshot, doc: .receipt) } + (0..<8).map { item("d\($0)", labels: ["dog"]) }
    let existing = [RuleSpec(name: "Dog", include: .init(kinds: [.camera], labels: ["dog"]))]
    let s = suggestAlbums(items, existing: existing, minCount: 6)
    #expect(s.map(\.spec.include.docTypes) == [[.receipt, .bill]])
}
@Test func sensitiveNeverSuggested() {
    let items = (0..<8).map { item("i\($0)", labels: ["dog"], sensitive: .card) }
    #expect(suggestAlbums(items, existing: [], minCount: 6).isEmpty)
}
