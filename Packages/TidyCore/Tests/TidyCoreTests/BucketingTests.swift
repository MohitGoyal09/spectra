import Foundation
import Testing
@testable import TidyCore

private let now = ISO8601DateFormatter().date(from: "2026-11-22T12:00:00Z")!
private func rec(daysAgo: Double = 0, _ edit: (inout PhotoRecord) -> Void = { _ in }) -> PhotoRecord {
    var r = PhotoRecord(id: "x", createdAt: now.addingTimeInterval(-daysAgo * 86_400))
    edit(&r)
    return r
}
private func verdict(_ r: PhotoRecord) -> Verdict { ruleVerdict(r, hits: scanText(r.ocrText, barcodes: r.barcodePayloads), now: now) }

@Test func cameraPhotoIsKept() {
    let r = rec { $0.cameraMake = "Apple"; $0.faceCount = 2 }
    let v = verdict(r)
    #expect(v.kind == .camera && v.verdict == .keep && bucket(for: v, record: r) == .realPhotos)
}
@Test func oldOTPScreenshotIsJunk() {
    let r = rec(daysAgo: 41) { $0.isScreenshot = true; $0.ocrText = "Your OTP is 482913. Valid 10 min" }
    let v = verdict(r)
    #expect(v.verdict == .junk && v.junkType == .expiredOTP && v.reason.contains("expired"))
    #expect(bucket(for: v, record: r) == .expiredScreenshots)
}
@Test func freshOTPIsReview() {
    let r = rec(daysAgo: 0.08) { $0.isScreenshot = true; $0.ocrText = "Your OTP is 482913" }
    #expect(verdict(r).verdict == .review)
}
@Test func pastTicketIsJunk() {
    let r = rec(daysAgo: 30) { $0.isScreenshot = true; $0.ocrText = "Boarding pass PNR AB12CD gate 4 on 3 Nov 2026" }
    let v = verdict(r)
    #expect(v.verdict == .junk && v.junkType == .expiredQR)
}
@Test func paymentIsReviewNotJunk() {
    let r = rec(daysAgo: 200) { $0.isScreenshot = true; $0.ocrText = "₹450 paid to ramesh@okicici UTR 1234" }
    let v = verdict(r)
    #expect(v.verdict == .review && v.junkType == .oldPayment)
}
@Test func whatsappGreetingIsForward() {
    let r = rec(daysAgo: 3) { $0.sourceAlbums = ["WhatsApp"]; $0.ocrText = "Good Morning! Have a blessed day"; $0.labels = ["flower"] }
    let v = verdict(r)
    #expect(v.verdict == .junk && v.junkType == .forward && bucket(for: v, record: r) == .forwards)
}
@Test func sensitiveIsKeptAndLocked() {
    let r = rec { $0.ocrText = "Permanent Account Number ABCDE1234F" }
    let v = verdict(r)
    #expect(v.verdict == .keep && v.sensitive == .pan && bucket(for: v, record: r) == .idsCards)
    #expect(!isPreselectable(v, record: r))
}
@Test func sensitiveBeatsCameraPhoto() {
    let r = rec { $0.cameraMake = "Apple"; $0.ocrText = "ICICI Bank Pay or bearer IFSC ICIC0001234" }
    #expect(verdict(r).sensitive == .bank)
}
@Test func favoriteNeverPreselected() {
    var v = verdict(rec(daysAgo: 41) { $0.isScreenshot = true; $0.ocrText = "OTP is 482913" })
    v.verdict = .junk
    #expect(!isPreselectable(v, record: rec { $0.isFavorite = true }))
}
@Test func cameraWithFacesNeverPreselected() {
    var v = verdict(rec { $0.cameraMake = "Apple" })
    v.verdict = .junk
    #expect(!isPreselectable(v, record: rec { $0.cameraMake = "Apple"; $0.faceCount = 1 }))
}
@Test func bigVideoThreshold() {
    let big = rec { $0.isVideo = true; $0.fileBytes = 250_000_000 }
    let small = rec { $0.isVideo = true; $0.fileBytes = 50_000_000 }
    #expect(verdict(big).junkType == .bigVideo && verdict(small).junkType == nil)
}
@Test func screenRecordingIsReview() {
    let r = rec { $0.isVideo = true; $0.isScreenRecording = true; $0.fileBytes = 1_200_000_000 }
    let v = verdict(r)
    #expect(v.junkType == .screenRecording && v.verdict == .review && v.reason.contains("1.2 GB"))
}
@Test func aiMadeIsReview() {
    let r = rec { $0.provenance = ProvenanceInput(software: "ChatGPT") }
    let v = verdict(r)
    #expect(v.junkType == .aiMade && v.reason == "Made with ChatGPT" && bucket(for: v, record: r) == .aiMade)
}
@Test func blurryCameraIsReview() {
    let r = rec { $0.cameraMake = "Apple"; $0.blurScore = 0.05 }
    #expect(verdict(r).junkType == .blurry && verdict(r).verdict == .review)
}
@Test func plainScreenshotGoesToOtherScreenshots() {
    let r = rec { $0.isScreenshot = true; $0.ocrText = "Employee discounts on headphones" }
    let v = verdict(r)
    #expect(v.verdict == .review && bucket(for: v, record: r) == .otherScreenshots)
}

// Splitting the large "received" pile (no camera EXIF, not a screenshot)
@Test func sharedScreenshotDetectedByStatusBar() {
    let r = rec { $0.labels = ["document", "screenshot"]; $0.ocrText = "6:08 LTE 91% Important Status & Timeline Details" }
    let v = verdict(r)
    #expect(v.kind == .screenshot && bucket(for: v, record: r) == .otherScreenshots && v.reason == "Screenshot someone sent you")
}
@Test func documentPhotoGoesToDocuments() {
    let r = rec { $0.labels = ["document", "printed_page"]; $0.ocrText = String(repeating: "Section 4 terms and conditions apply. ", count: 4) }
    let v = verdict(r)
    #expect(v.kind == .document && bucket(for: v, record: r) == .documents)
}
@Test func receivedPhotoOfPeople() {
    let r = rec { $0.labels = ["people", "adult", "outdoor"]; $0.faceCount = 3 }
    let v = verdict(r)
    #expect(v.kind == .received && bucket(for: v, record: r) == .receivedPhotos && v.verdict == .review)
}
@Test func memeWithCaption() {
    let r = rec { $0.labels = ["sign", "structure"]; $0.ocrText = "SORRY GUYS MOM SAID NO" }
    let v = verdict(r)
    #expect(v.junkType == .meme && bucket(for: v, record: r) == .memes)
}
@Test func receivedPhotoNeverPreselected() {
    var v = verdict(rec { $0.labels = ["people"]; $0.faceCount = 1 })
    v.verdict = .junk
    #expect(!isPreselectable(v, record: rec { $0.labels = ["people"]; $0.faceCount = 1 }))
}
