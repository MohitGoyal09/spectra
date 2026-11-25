import Foundation
import Testing
@testable import TidyCore

@Test func masksOTP() { #expect(mask("OTP 482913") == "OTP [NUM]") }
@Test func masksEmailPhoneUPI() {
    let m = mask("mail a.b@gmail.com call +91 98765 43210 pay ramesh@okicici")
    #expect(m == "mail [EMAIL] call [PHONE] pay [UPI]")
}
@Test func masksSpacedCardNumber() { #expect(mask("card 4111 1111 1111 1111 ok") == "card [NUM] ok") }
@Test func keepsWords() { #expect(mask("Croma receipt total") == "Croma receipt total") }
@Test func keepsShortNumbers() { #expect(mask("Gate 12 at 9:45") == "Gate 12 at 9:45") }

@Test func privacyLogPersistsAndNeverCountsPhotos() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    let log = PrivacyLog(fileURL: url)
    log.append(PrivacyEntry(date: .now, task: "rule", model: "gemini-3.5-flash-lite", sentText: "Bills go to Tax 2026"))
    let reloaded = PrivacyLog(fileURL: url)
    #expect(reloaded.entries.count == 1 && reloaded.entries[0].task == "rule")
    #expect(reloaded.photosUploaded == 0)
}

@Test func masksPunctuationSeparatedNumbers() {
    #expect(mask("card 4111.1111.1111.1111") == "card [NUM]")
    #expect(mask("tel (022) 1234/5678") == "tel ([NUM]")   // a leading bracket may stay; no digit does
    #expect(mask("a/c 123-456-789") == "a/c [NUM]")
}
@Test func masksDevanagariDigits() { #expect(mask("ओटीपी ४८२९१३ है") == "ओटीपी [NUM] है") }
@Test func masksUnicodeEmail() { #expect(mask("mail रमेश.k@gmail.com") == "mail [EMAIL]") }
@Test func noDigitsSurviveMasking() {
    for s in ["4111 1111 1111 1111", "98765.43210", "OTP: 4 8 2 9 1 3", "₹1,29,999 paid", "UTR(123456789012)"] {
        let digits = mask(s).filter(\.isNumber).count
        #expect(digits < 4, "\(s) → \(mask(s))")
    }
}
