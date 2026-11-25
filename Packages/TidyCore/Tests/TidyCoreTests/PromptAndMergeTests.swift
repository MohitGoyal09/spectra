import Foundation
import Testing
@testable import TidyCore

private let now = Date()
private func rec(_ id: String, _ edit: (inout PhotoRecord) -> Void = { _ in }) -> PhotoRecord {
    var r = PhotoRecord(id: id, createdAt: now); edit(&r); return r
}
private func rule(_ edit: (inout Verdict) -> Void = { _ in }) -> Verdict {
    var v = Verdict(id: "a", kind: .screenshot, verdict: .review, reason: "Screenshot", confidence: 0.4, source: .rules); edit(&v); return v
}

@Test func promptMasksForCloud() {
    let r = rec("a") { $0.ocrText = "Your OTP is 482913"; $0.isScreenshot = true }
    let p = judgePrompt(records: [(r, scanText(r.ocrText, barcodes: []))], forCloud: true, now: now)
    #expect(p.contains("[NUM]") && !p.contains("482913"))
}
@Test func promptOmitsSensitiveForCloud() {
    let r = rec("id") { $0.ocrText = "ABCDE1234F" }
    let ok = rec("ok") { $0.ocrText = "hello" }
    let p = judgePrompt(records: [(r, scanText(r.ocrText, barcodes: [])), (ok, scanText(ok.ocrText, barcodes: []))], forCloud: true, now: now)
    #expect(!p.contains("id |") && p.contains("ok |"))
}
@Test func promptTrimsOCRTo100() {
    let r = rec("a") { $0.ocrText = String(repeating: "x", count: 500) }
    #expect(judgePrompt(records: [(r, RuleHits())], forCloud: false, now: now).count < 260)
}
@Test func modelNeverChangesVerdict() {
    let note = ModelNote(id: "a", kind: .forward, title: "Greeting card")
    let m = merge(rule: rule(), note: note, ocrText: "", topLabel: nil)
    #expect(m.verdict == .review && m.junkType == nil)
}
@Test func rulesSensitiveWins() {
    let note = ModelNote(id: "a", kind: .download, title: "Some card", savedInfo: SavedInfo(type: "id", title: "x", fields: [:]))
    let m = merge(rule: rule { $0.sensitive = .pan; $0.verdict = .keep; $0.reason = "Looks like a PAN card — lock it" }, note: note, ocrText: "", topLabel: nil)
    #expect(m.sensitive == .pan && m.savedInfo == nil && m.reason.contains("PAN"))
}
@Test func genericReasonReplacedByTitle() {
    let m = merge(rule: rule(), note: ModelNote(id: "a", kind: nil, title: "Employee discount notice"), ocrText: "", topLabel: nil)
    #expect(m.reason == "Employee discount notice" && m.source == .onDevice)
}
@Test func specificRuleReasonKept() {
    let r = rule { $0.reason = "OTP from 12 Oct, expired"; $0.verdict = .junk; $0.junkType = .expiredOTP }
    #expect(merge(rule: r, note: ModelNote(id: "a", kind: nil, title: "OTP code"), ocrText: "", topLabel: nil).reason == "OTP from 12 Oct, expired")
}
@Test func copiedReasonReplacedByLabel() {
    let ocr = "Make this repo's CI as fast as possible without letting it lie"
    let m = merge(rule: rule(), note: ModelNote(id: "a", kind: nil, title: "Make this repo's CI as fast as possible"), ocrText: ocr, topLabel: "document")
    #expect(m.reason == "Document")
}
@Test func echoedInstructionReplaced() {
    let m = merge(rule: rule(), note: ModelNote(id: "a", kind: nil, title: "Under 10 plain words naming what the photo shows"), ocrText: "", topLabel: "laptop")
    #expect(m.reason == "Laptop")
}
@Test func missingNoteFallsBackToRule() {
    #expect(merge(rule: rule(), note: nil, ocrText: "", topLabel: nil).reason == "Screenshot")
}
@Test func cameraKindNeedsRuleAgreement() {
    let m = merge(rule: rule { $0.kind = .download }, note: ModelNote(id: "a", kind: .camera, title: nil), ocrText: "", topLabel: nil)
    #expect(m.kind == .download)
    let d = merge(rule: rule { $0.kind = .download }, note: ModelNote(id: "a", kind: .document, title: nil), ocrText: "", topLabel: nil)
    #expect(d.kind == .document)
}

@Test func cloudPromptMasksBeforeTruncating() {
    // The number straddles the 100-character cut; no fragment of it may reach the cloud.
    let filler = String(repeating: "a", count: 97)
    let r = rec("a") { $0.ocrText = filler + " 482913 tail ramesh.kumar@gmail.com" }
    let p = judgePrompt(records: [(r, RuleHits())], forCloud: true, now: now)
    #expect(!p.contains("48") && !p.contains("ramesh"))
}

@Test func onlyGenericNonSensitiveVerdictsWantNotes() {
    #expect(wantsNote(rule()))
    #expect(!wantsNote(rule { $0.reason = "OTP from 12 Oct, expired" }))
    #expect(!wantsNote(rule { $0.sensitive = .pan }))
}

@Test func modelMayOnlyRefineToDocumentOrForward() {
    #expect(merge(rule: rule { $0.kind = .download }, note: ModelNote(id: "a", kind: .recording, title: nil), ocrText: "", topLabel: nil).kind == .download)
    #expect(merge(rule: rule { $0.kind = .download }, note: ModelNote(id: "a", kind: .screenshot, title: nil), ocrText: "", topLabel: nil).kind == .download)
    #expect(merge(rule: rule { $0.kind = .download }, note: ModelNote(id: "a", kind: .forward, title: nil), ocrText: "", topLabel: nil).kind == .forward)
}
@Test func savedInfoNeedsADetail() {
    let empty = ModelNote(id: "a", kind: nil, title: "Recipe", savedInfo: SavedInfo(type: "recipe", title: "Recipe", fields: [:]))
    #expect(merge(rule: rule(), note: empty, ocrText: "", topLabel: nil).savedInfo == nil)
    let real = ModelNote(id: "a", kind: nil, title: "Uber ride", savedInfo: SavedInfo(type: "transit", title: "Uber ride", fields: ["detail": "14 Dec 9:30"]))
    #expect(merge(rule: rule(), note: real, ocrText: "", topLabel: nil).savedInfo != nil)
}
