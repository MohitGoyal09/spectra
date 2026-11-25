import XCTest
import CoreGraphics
@testable import TidyRoll

/// Runs the bundled CLIP models on the device: tokenizer, text encoder and image encoder end to end.
final class ClipModelTests: XCTestCase {
    private func cos(_ a: [Float], _ b: [Float]) -> Float { ClipModel.similarities(a, [b])[0] }

    func testTextMeaningIsCloseForSynonyms() async throws {
        await ClipModel.warmUp()
        let m = try XCTUnwrap(ClipModel.ready, "CLIP models not bundled")
        let dog = try XCTUnwrap(m.embed(text: "a photo of a dog"))
        let puppy = try XCTUnwrap(m.embed(text: "a photo of a puppy"))
        let receipt = try XCTUnwrap(m.embed(text: "a photo of a shop receipt"))
        XCTAssertEqual(dog.count, 512)
        XCTAssertGreaterThan(cos(dog, puppy), cos(dog, receipt) + 0.05)
    }

    func testImageGivesUnitVector() async throws {
        await ClipModel.warmUp()
        let m = try XCTUnwrap(ClipModel.ready, "CLIP models not bundled")
        let ctx = CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        let v = try XCTUnwrap(m.embed(ctx.makeImage()!))
        XCTAssertEqual(v.count, 512)
        XCTAssertEqual(cos(v, v), 1, accuracy: 0.01)
        let red = try XCTUnwrap(m.embed(text: "a red background")), cat = try XCTUnwrap(m.embed(text: "a cat sleeping on a sofa"))
        XCTAssertGreaterThan(cos(v, red), cos(v, cat), "a plain red picture is closer to 'red' than to 'cat'")
    }
}
