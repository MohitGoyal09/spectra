import Testing
@testable import TidyCore

// A Verhoeff-valid, specimen-only 12-digit number (starts 2-9). Not a real Aadhaar.
private func specimenAadhaar() -> String {
    let base = "93456781234"
    for d in 0...9 where verhoeffValid(base + String(d)) { return base + String(d) }
    return base + "0"
}

@Test func otpDetected() { #expect(scanText("Your OTP is 482913. Valid 10 min", barcodes: []).otp) }
@Test func otpIgnoresPlainNumbers() { #expect(!scanText("Order 482913 shipped today", barcodes: []).otp) }
@Test func aadhaarRequiresVerhoeff() {
    let good = specimenAadhaar()
    #expect(scanText("SPECIMEN \(good.prefix(4)) \(good.dropFirst(4).prefix(4)) \(good.suffix(4))", barcodes: []).sensitive == .aadhaar)
    let last = Int(String(good.last!))!
    let bad = good.dropLast() + String((last + 1) % 10)
    #expect(scanText("SPECIMEN \(bad)", barcodes: []).sensitive == nil)
}
@Test func panDetected() { #expect(scanText("Permanent Account Number ABCDE1234F", barcodes: []).sensitive == .pan) }
@Test func cardRequiresLuhn() {  // grouped 4-4-4-4
    #expect(scanText("Card 4111 1111 1111 1111", barcodes: []).sensitive == .card)
    #expect(scanText("Card 4111 1111 1111 1112", barcodes: []).sensitive == nil)
}
@Test func upiPaymentDetected() { #expect(scanText("₹450 paid to ramesh@okicici UTR 1234", barcodes: []).payment) }
@Test func qrPayloadMarksTicket() { #expect(scanText("", barcodes: ["https://x.example"]).ticketOrQR) }
@Test func receiptDocType() { #expect(scanText("GST invoice total ₹1,299", barcodes: []).docType == .receipt) }
@Test func greetingDetected() { #expect(scanText("Good Morning! Have a blessed day", barcodes: []).greeting) }
@Test func sensitiveSetsIdDocType() { #expect(scanText("ABCDE1234F", barcodes: []).docType == .id) }

@Test func festivalGreetingDetected() {
    #expect(scanText("Wishing you all and your families a very Happy Diwali!", barcodes: []).greeting)
    #expect(scanText("Happy New Year 2027 to you and family", barcodes: []).greeting)
}
@Test func plainHappyIsNotGreeting() { #expect(!scanText("I am happy with the CI speed", barcodes: []).greeting) }
@Test func chequeIsSensitiveBank() {
    #expect(scanText("ICICI Bank Pay or bearer Rupees A/c No IFSC ICIC0001234", barcodes: []).sensitive == .bank)
}

@Test func luhnNumberAloneIsNotACard() {
    // Handwriting OCR can produce a Luhn-valid digit run; without card words or 4-4-4-4 grouping it is not a card.
    #expect(scanText("Name Mosit Subject DW 4111111111111111 page", barcodes: []).sensitive == nil)
}
@Test func groupedCardNumberIsACard() { #expect(scanText("4111 1111 1111 1111", barcodes: []).sensitive == .card) }
@Test func cardWordsWithNumberIsACard() { #expect(scanText("VISA debit 4111111111111111 valid thru", barcodes: []).sensitive == .card) }
