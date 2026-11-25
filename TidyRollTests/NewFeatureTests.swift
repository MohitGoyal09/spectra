import UniformTypeIdentifiers
import ImageIO
import XCTest
import SwiftUI
import TidyCore
@testable import TidyRoll

@MainActor final class NewFeatureTests: XCTestCase {
    /// Real on-device AI, whatever the demo switch was left at.
    override func setUp() async throws { UserDefaults.standard.set(false, forKey: "simulateNoOnDevice") }

    func testTicketBecomesEventOnDevice() async throws {
        let judge = HybridJudge(log: PrivacyLog(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("ev-\(UUID()).json")))
        try XCTSkipUnless(judge.status == .available, "On-device model not available")
        let d = try await judge.eventDraft(text: "BOARDING PASS IndiGo 6E 2134 PNR X7K2QP Delhi DEL to Goa GOI Date 14 Dec 2026 Departure 06:45 Gate 12",
                                           today: ISO8601DateFormatter().date(from: "2026-11-23T00:00:00Z")!)
        XCTAssertTrue(d.title.localizedCaseInsensitiveContains("goa"), d.title)
        let start = try XCTUnwrap(HybridJudge.startDate(d.start), "no date in \(d.start)")
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: start.0)
        XCTAssertEqual([c.year, c.month, c.day], [2026, 12, 14])
    }

    func testDemoSwitchFallsBackWithoutOnDevice() {
        let judge = HybridJudge(log: PrivacyLog(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("d-\(UUID()).json")))
        let before = judge.simulateNoOnDevice
        defer { judge.simulateNoOnDevice = before }
        judge.simulateNoOnDevice = true
        XCTAssertEqual(judge.status, .notEligible)
    }

    func testFreedCardRenders() {
        XCTAssertNotNil(FreedCard.image(freedBytes: 1_400_000_000, items: 120))
    }

    func testWidgetSummaryRoundTrips() {
        let s = WidgetSummary(freeableBytes: 42, reviewBytes: 7, expiredScreenshots: 3, duplicates: 5, forwards: 1, updated: .now)
        let saved = WidgetSummary.load()
        defer { saved?.save() }
        s.save()
        XCTAssertEqual(WidgetSummary.load()?.freeableBytes, 42, "App Group storage works")
    }
}

@MainActor final class CleanAsYouGoTests: XCTestCase {
    private func shot(_ text: String, ago: TimeInterval) -> IndexedItem {
        var r = PhotoRecord(id: UUID().uuidString, createdAt: Date().addingTimeInterval(-ago)); r.isScreenshot = true; r.ocrText = text
        let v = Verdict(id: r.id, kind: .screenshot, verdict: .review, reason: "Screenshot", confidence: 1, source: .rules)
        return IndexedItem(record: r, verdict: v, dHash: 0, faceQuality: 0, blurScore: nil)
    }

    func testFreshOTPGetsAReminderAfterADay() {
        let item = shot("Your OTP is 482913. Do not share.", ago: 600)
        let r = CleanAsYouGo.reminders([item])
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].fireAt.timeIntervalSince(item.record.createdAt), RuleConfig.otpExpiryDays * 86_400, accuracy: 1)
    }

    func testOldOTPAndPlainScreenshotsGetNone() {
        XCTAssertTrue(CleanAsYouGo.reminders([shot("Your OTP is 482913", ago: 3 * 86_400), shot("Nice sunset", ago: 60)]).isEmpty)
    }
}

@MainActor final class AlbumLockAndJPEGTests: XCTestCase {
    func testLockRoundTrips() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "AlbumLockTests")); d.removePersistentDomain(forName: "AlbumLockTests")
        AlbumLock.setLocked("A/1", true, in: d); AlbumLock.setLocked("B/2", true, in: d)
        XCTAssertTrue(AlbumLock.isLocked("A/1", in: d))
        AlbumLock.setLocked("A/1", false, in: d)
        XCTAssertFalse(AlbumLock.isLocked("A/1", in: d))
        XCTAssertTrue(AlbumLock.isLocked("B/2", in: d))
    }

    func testHEICIsResavedAsJPEGAndOthersAreLeftAlone() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let img = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { c in UIColor.red.setFill(); c.fill(.init(x: 0, y: 0, width: 40, height: 30)) }
        let heic = dir.appendingPathComponent("IMG_1.HEIC")
        let dst = try XCTUnwrap(CGImageDestinationCreateWithURL(heic as CFURL, UTType.heic.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dst, try XCTUnwrap(img.cgImage), nil); XCTAssertTrue(CGImageDestinationFinalize(dst))

        let jpg = try XCTUnwrap(Gallery.jpegCopy(of: heic))
        XCTAssertEqual(jpg.lastPathComponent, "IMG_1.jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: heic.path))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(jpg as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(src) as String?, UTType.jpeg.identifier)

        XCTAssertNil(Gallery.jpegCopy(of: jpg), "a JPEG is shared as it is")
    }
}
