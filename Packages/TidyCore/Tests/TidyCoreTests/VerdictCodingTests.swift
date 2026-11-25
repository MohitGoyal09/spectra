import Foundation
import Testing
@testable import TidyCore

@Test func decodesModelJSONWithSnakeCase() throws {
    let json = #"[{"id":"a","kind":"screenshot","verdict":"junk","reason":"OTP from 12 Oct, expired","junk_type":"expired_otp","confidence":0.9}]"#
    let v = try JSONDecoder().decode([Verdict].self, from: Data(json.utf8))
    #expect(v[0].junkType == .expiredOTP && v[0].verdict == .junk)
    #expect(v[0].source == .onDevice)
}

@Test func unknownEnumValueFailsDecode() {
    let json = #"[{"id":"a","kind":"selfie","verdict":"junk","reason":"x","confidence":1}]"#
    #expect(throws: (any Error).self) { try JSONDecoder().decode([Verdict].self, from: Data(json.utf8)) }
}
