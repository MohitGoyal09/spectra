import XCTest

/// Looks at Apple's own Photos app on this iPhone, read-only, to compare features with Spectra.
/// It only searches and opens collections; it never edits, deletes, hides or shares anything.
@MainActor final class ApplePhotosComparison: XCTestCase {
    private let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")

    override func setUp() async throws { continueAfterFailure = true }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: photos.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    /// Fresh Photos each time, open Search (bottom-right), type into the focused box, submit.
    private func search(_ q: String) {
        photos.terminate(); photos.launch(); sleep(3)
        photos.coordinate(withNormalizedOffset: CGVector(dx: 0.89, dy: 0.945)).tap(); sleep(2)
        if !photos.keyboards.firstMatch.exists {
            let box = photos.textFields.firstMatch.exists ? photos.textFields.firstMatch : photos.searchFields.firstMatch
            if box.waitForExistence(timeout: 4) { box.tap() }
        }
        guard photos.keyboards.firstMatch.waitForExistence(timeout: 4) else { return snap("No keyboard for \(q)") }
        photos.typeText(q + "\n")
        sleep(7)
        snap("Apple Photos search: \(q)")
    }

    func testApplePhotosSearch() {
        for q in ["dog at the beach", "receipts from swiggy", "What's the wifi password?", "expired OTP", "aadhaar card", "photos from goa", "blurry photos"] {
            search(q)
        }
        photos.terminate()
    }

    func testApplePhotosFeatures() {
        photos.launch()
        sleep(4); snap("Apple Photos home")
        photos.swipeUp(); sleep(2); snap("Apple Photos collections 1")
        photos.swipeUp(); sleep(2); snap("Apple Photos collections 2")
        photos.swipeUp(); sleep(2); snap("Apple Photos collections 3")

        for name in ["Utilities", "Duplicates", "Receipts", "Screenshots"] {
            let b = photos.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            if b.waitForExistence(timeout: 3), b.isHittable { b.tap(); sleep(3); snap("Apple Photos: \(name)"); photos.navigationBars.buttons.firstMatch.tap(); sleep(1) }
        }

        for q in ["dog at the beach", "receipts from swiggy", "What's the wifi password?", "expired OTP", "aadhaar card", "photos from goa"] {
            search(q)
        }
        photos.terminate()
    }
}
