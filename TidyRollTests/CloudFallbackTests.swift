import XCTest
import TidyCore
@testable import TidyRoll

/// Real Gemini call through Firebase AI Logic (needs network and App Check debug token). Shows the fallback path works.
@MainActor final class CloudFallbackTests: XCTestCase {
    func testRuleCompilesThroughGeminiWhenOnDeviceIsOff() async throws {
        let judge = HybridJudge(log: PrivacyLog(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("cf-\(UUID()).json")))
        let (sim, consent) = (judge.simulateNoOnDevice, judge.cloudConsent)
        defer { judge.simulateNoOnDevice = sim; judge.cloudConsent = consent }
        judge.simulateNoOnDevice = true
        judge.cloudConsent = true
        do {
            let spec = try await judge.compileRule("receipts from swiggy", labels: ["document"])
            XCTAssertFalse(judge.lastOnDevice)
            print("CLOUD SPEC:", spec)
        } catch {
            XCTFail("Gemini fallback failed: \(error)")
        }
    }
}
