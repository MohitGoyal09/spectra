import XCTest
import TidyCore
@testable import TidyRoll

final class RuleCompilerTests: XCTestCase {
    func testDraftBecomesSpec() {
        let d = RuleDraft(name: " Tax 2026 ", kinds: [], junkTypes: [], docTypes: [.bill, .receipt], keywords: [" Invoice "], labels: [], visual: "",
                          dateFrom: "2026-01-01", dateTo: "2026-03-31")
        let s = HybridJudge.spec(from: d)
        XCTAssertEqual(s.name, "Tax 2026")
        XCTAssertEqual(s.include.docTypes, [.bill, .receipt])
        XCTAssertEqual(s.include.keywords, ["invoice"])
        XCTAssertNil(s.include.kinds, "empty lists mean no condition")
        XCTAssertNotNil(s.include.dateFrom)
        XCTAssertEqual(Calendar(identifier: .gregorian).dateComponents(in: .current, from: s.include.dateTo!).day, 31, "the end date covers the whole day")
    }

    func testJunkEnumNamesMatchCore() {
        let d = RuleDraft(name: "x", kinds: [.screenshot], junkTypes: [.expired_otp, .big_video], docTypes: [], keywords: [], labels: [], visual: "", dateFrom: "", dateTo: "")
        let s = HybridJudge.spec(from: d)
        XCTAssertEqual(s.include.junkTypes, [.expiredOTP, .bigVideo])
        XCTAssertEqual(s.include.kinds, [.screenshot])
    }

    func testUnknownLabelBecomesKeyword() {
        let d = RuleDraft(name: "Dog", kinds: [.camera], junkTypes: [], docTypes: [], keywords: [], labels: ["dog", "puppy"], visual: "a dog", dateFrom: "", dateTo: "")
        let s = HybridJudge.spec(from: d, vocabulary: ["dog", "sunset_sunrise"])
        XCTAssertEqual(s.include.labels, ["dog"])
        XCTAssertEqual(s.include.keywords, ["puppy"], "a label this library never saw is searched as text")
    }

    func testPictureOnlySentenceKeepsWords() {
        let d = RuleDraft(name: "Girls", kinds: [.camera], junkTypes: [], docTypes: [], keywords: [], labels: [], visual: "a girl", dateFrom: "", dateTo: "")
        let s = HybridJudge.spec(from: d, vocabulary: ["people"])
        XCTAssertEqual(s.visual, "a girl")
        XCTAssertEqual(s.include.keywords, ["girl"], "still matches through labels when picture search is off")
    }
}
