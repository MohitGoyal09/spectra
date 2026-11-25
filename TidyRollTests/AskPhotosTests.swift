import XCTest
import TidyCore
@testable import TidyRoll

/// Runs the real on-device model (skipped where Apple Intelligence is off). Proves the Ask path end to end.
@MainActor final class AskPhotosTests: XCTestCase {
    /// Real on-device AI, whatever the demo switch was left at.
    override func setUp() async throws { UserDefaults.standard.set(false, forKey: "simulateNoOnDevice") }

    private func item(_ id: String, _ text: String, sensitive: Sensitive? = nil) -> IndexedItem {
        var r = PhotoRecord(id: id, createdAt: .now); r.ocrText = text
        var v = Verdict(id: id, kind: .screenshot, verdict: .review, reason: "Screenshot", confidence: 1, source: .rules)
        v.sensitive = sensitive
        return IndexedItem(record: r, verdict: v, dHash: 0, faceQuality: 0, blurScore: nil)
    }

    func testAnswersWifiPasswordOnDevice() async throws {
        let log = PrivacyLog(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("ask-log-\(UUID()).json"))
        let judge = HybridJudge(log: log)
        try XCTSkipUnless(judge.status == .available, "On-device model not available")
        let items = [item("a", "Guest Wi-Fi network: CafeBlue password: tea4two"), item("b", "Your Swiggy order is on the way"),
                     item("c", "PAN card ABCDE1234F", sensitive: .pan)]
        let r = try await judge.ask("What's the wifi password?", items: items)
        XCTAssertEqual(r?.sourceIDs.first, "a")
        XCTAssertTrue(r?.answer.contains("tea4two") == true, r?.answer ?? "no answer")
        XCTAssertTrue(r?.onDevice == true)
        XCTAssertTrue(log.entries.isEmpty, "nothing went to the cloud")
    }

    func testIDsAreNeverRetrieved() async throws {
        let judge = HybridJudge(log: PrivacyLog(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("ask-\(UUID()).json")))
        let r = try await judge.ask("What is my PAN number?", items: [item("c", "PAN card ABCDE1234F", sensitive: .pan)])
        XCTAssertNil(r)
    }
}
