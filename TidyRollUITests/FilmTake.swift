import XCTest

/// Drives the demo-video take in film mode (`-film`: only the "Spectra Film" and "Spectra Demo" albums are visible).
/// Run the tests in order while the screen is recorded. Each step prints `FILM-MARK <name> <unix time>`, so the edit
/// can find it in the recording. Get me space deletes the videos it picks (they go to Recently Deleted).
@MainActor final class FilmTake: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-film", "-uitest-light"]
        // A fixed App Check debug token for the Simulator, passed in by the runner (TEST_RUNNER_FILM_APPCHECK_TOKEN),
        // never stored in the repo. Firebase's debug provider reads FIRAAppCheckDebugToken.
        if let token = ProcessInfo.processInfo.environment["FILM_APPCHECK_TOKEN"] {
            app.launchEnvironment["FIRAAppCheckDebugToken"] = token
        }
        app.launch()
        for label in ["Allow Full Access", "Allow", "OK"] {
            let b = springboard.alerts.buttons[label].firstMatch
            if b.waitForExistence(timeout: 1) { b.tap() }
        }
    }

    private func mark(_ name: String) { print("FILM-MARK \(name) \(Date().timeIntervalSince1970)") }

    private func hold(_ s: Double = 1.5) { Thread.sleep(forTimeInterval: s) }

    @discardableResult
    private func tap(_ e: XCUIElement, _ what: String, wait: TimeInterval = 8) -> Bool {
        guard e.waitForExistence(timeout: wait), e.isHittable else { XCTFail("Missing: \(what)"); return false }
        // The frame (in points) lets the edit draw a tap ring where the finger would be.
        let f = e.frame
        mark("tap:\(what) @\(Int(f.midX)),\(Int(f.midY))"); e.tap(); return true
    }

    private func starting(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func text(_ contains: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", contains)).firstMatch
    }

    private func tab(_ name: String) { tap(app.tabBars.buttons[name].firstMatch, "tab \(name)") }

    private func back() { app.navigationBars.buttons.firstMatch.tap(); hold(1) }

    private func type(_ s: String, into e: XCUIElement) {
        mark("type-start"); e.typeText(s); mark("type-end")
    }

    // MARK: The take, in film order

    func test1_Scan() {
        tab("Library")
        // The toolbar button is "Scan" before the first scan and "Scan again" after; the empty state has "Scan my photos".
        let scan = ["Scan my photos", "Scan", "Scan again"].map { app.buttons[$0].firstMatch }.first { $0.waitForExistence(timeout: 2) }
        guard let scan, tap(scan, "scan") else { return XCTFail("No scan button") }
        mark("scan-start")
        XCTAssertTrue(app.buttons["Review what can go"].waitForExistence(timeout: 300), "Scan did not finish")
        mark("scan-done"); hold(2)
        // Replay plays the globe again with every thumbnail loaded: the hero shot of the film.
        if tap(app.buttons["Replay"].firstMatch, "replay") { mark("replay-start"); hold(14); mark("replay-done") }
        tap(app.buttons["Review what can go"].firstMatch, "review what can go"); hold(2)
    }

    func test2_Reasons() {
        tab("Clean Up"); hold()
        for bucket in ["Expired screenshots", "Forwards", "Duplicates"] {
            app.swipeUp(velocity: .slow)
            if tap(starting(bucket), bucket) {
                mark("bucket:\(bucket)"); hold(1.5)
                // The viewer's header carries the reason ("OTP from 20 Nov · expired").
                if tap(app.buttons["Photo"].firstMatch, "first photo in \(bucket)") {
                    mark("reason:\(bucket)"); hold(3)
                    app.buttons["Back"].firstMatch.exists ? app.buttons["Back"].firstMatch.tap() : app.navigationBars.buttons.firstMatch.tap()
                    hold(1)
                }
                back()
            }
            app.swipeDown(velocity: .slow)
        }
    }

    func test3_GetSpace() {
        tab("Clean Up")
        guard tap(app.buttons["Get me space"].firstMatch, "get me space") else { return }
        hold()
        mark("plan-ready"); hold(3)   // 1 GB is the default target
        let slider = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Slide to free'")).firstMatch
        guard slider.waitForExistence(timeout: 5) else { return XCTFail("No slider") }
        mark("slide")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)))
        for host in [app!, springboard] {
            let b = host.alerts.buttons["Delete"].firstMatch
            if b.waitForExistence(timeout: 5) { mark("confirm-delete"); b.tap(); break }
        }
        XCTAssertTrue(text("Freed").waitForExistence(timeout: 30), "No Freed card")
        mark("freed"); hold(3)
        app.buttons["Close"].firstMatch.tap()
    }

    func test4_Ask() {
        tab("Search")
        let field = app.searchFields.firstMatch
        guard field.waitForExistence(timeout: 6) else { return XCTFail("No search field") }
        field.tap()
        type("What's the Wi-Fi password?", into: field)
        XCTAssertTrue(text("brew2026").waitForExistence(timeout: 60), "Ask did not answer")
        mark("answer"); hold(3)
        field.buttons["Clear text"].firstMatch.tap()
    }

    func test5_IDLock() {
        tab("Clean Up")
        app.swipeUp(velocity: .slow)
        guard tap(starting("IDs & cards"), "IDs & cards") else { return }
        hold()
        tap(app.buttons["Photo"].firstMatch, "the SAMPLE ID"); hold(1.5)
        guard tap(app.buttons["Lock in Hidden album"].firstMatch, "lock") else { return }
        for host in [springboard, app!] {   // iOS's own prompt lives in SpringBoard
            let b = host.alerts.buttons["Hide"].firstMatch
            if b.waitForExistence(timeout: 3) { mark("confirm-hide"); b.tap(); break }
        }
        XCTAssertTrue(text("Locked in your Hidden album").waitForExistence(timeout: 10))
        mark("locked"); hold(2)
    }

    func test6_AlbumFromSentence() {
        tab("Collections")
        guard tap(app.buttons["New smart album"].firstMatch, "new smart album") else { return }
        let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        guard field.waitForExistence(timeout: 3) else { return XCTFail("No sentence field") }
        field.tap()
        type("Bills and receipts go to Tax 2026", into: field)
        tap(app.buttons["Next"].firstMatch, "next")
        XCTAssertTrue(text("photos match").waitForExistence(timeout: 60), "Rule not understood")
        mark("match"); hold(2.5)
        tap(app.buttons["Save"].firstMatch, "save"); hold(3)
        mark("album-saved")
    }

    func test7_HybridFallback() {
        tab("Library")
        guard tap(app.buttons["aiStatusDot"].firstMatch, "AI dot"), tap(app.buttons["Open privacy log"].firstMatch, "privacy log") else { return }
        let cloud = app.switches["Cloud help (masked text)"].firstMatch
        let demo = app.switches["Simulate no on-device AI"].firstMatch
        guard cloud.waitForExistence(timeout: 5) else { return XCTFail("No cloud switch") }
        if (cloud.value as? String) != "1" { cloud.switches.firstMatch.tap() }
        hold(1)
        if (demo.value as? String) != "1" { mark("simulate-on"); demo.switches.firstMatch.tap() }
        hold(2)
        app.buttons["Done"].firstMatch.tap()
        tab("Search")
        let field = app.searchFields.firstMatch
        field.tap()
        type("receipts from swiggy", into: field)
        let badge = app.descendants(matching: .any)["Answered by Gemini from masked text"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 60), "No Gemini badge")
        mark("gemini-badge"); hold(3)
        field.typeText("\n"); hold(1)
        tab("Library")
        tap(app.buttons["aiStatusDot"].firstMatch, "AI dot"); hold(1)
        tap(app.buttons["Open privacy log"].firstMatch, "privacy log")
        mark("privacy-log"); hold(4)
        app.swipeUp(velocity: .slow); hold(2)
        // Leave the app as it was.
        if (demo.value as? String) == "1" { demo.switches.firstMatch.tap() }
        app.buttons["Done"].firstMatch.tap()
    }

    /// Needs a fresh OTP screenshot (taken today) in the film album and a scan after it. Film mode fires the reminder
    /// 10 s after it is scheduled and shows it as a banner inside Spectra.
    func test8_Reminder() {
        tab("Library")
        guard tap(app.buttons["aiStatusDot"].firstMatch, "AI dot"), tap(app.buttons["Open privacy log"].firstMatch, "privacy log") else { return }
        let toggle = app.switches["Clean as you go"].firstMatch
        guard toggle.waitForExistence(timeout: 5) else { return XCTFail("No Clean as you go switch") }
        if (toggle.value as? String) == "1" { toggle.switches.firstMatch.tap(); hold(1) }   // off, then on: reschedule now
        toggle.switches.firstMatch.tap()
        for label in ["Allow", "OK"] {
            let b = springboard.alerts.buttons[label].firstMatch
            if b.waitForExistence(timeout: 2) { b.tap() }
        }
        mark("reminder-scheduled")
        app.buttons["Done"].firstMatch.tap()
        tab("Library")
        let banner = springboard.otherElements.containing(NSPredicate(format: "label CONTAINS[c] 'OTP has expired'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 25), "No reminder banner")
        mark("reminder-banner"); hold(2)
        banner.tap(); mark("tap:reminder"); hold(3)
    }

    /// Prep only, on a fresh Simulator: opens the keyboard once and dismisses iOS's one-time keyboard tips, so they
    /// never cover the take.
    func test0_Warmup() {
        tab("Search")
        let field = app.searchFields.firstMatch
        guard field.waitForExistence(timeout: 6) else { return }
        field.tap(); hold(2)
        for _ in 0..<3 {
            let b = app.buttons["Continue"].firstMatch
            if b.waitForExistence(timeout: 3) { b.tap(); hold(1) }
        }
        field.typeText("warm up"); hold(1)
        for _ in 0..<2 {
            let b = app.buttons["Continue"].firstMatch
            if b.waitForExistence(timeout: 2) { b.tap(); hold(1) }
        }
        mark("warm")
    }

    /// Prep only: wipes the film albums and imports Documents/FilmImport again (copy the files in first and delete
    /// the TidyRoll-Film data folder while the app is closed).
    func test0_Reset() {
        app.terminate()
        app.launchArguments += ["-film-reset", "-film-import"]
        app.launch()
        for host in [app!, springboard] {
            let b = host.alerts.buttons["Delete"].firstMatch
            if b.waitForExistence(timeout: 10) { b.tap(); break }
        }
        hold(40)   // import of ~320 files
        mark("reset-done")
    }

    /// Prep only (not part of the film): shows the demo OTP photo full screen so the Simulator screen can be captured
    /// as the OTP screenshot.
    func test0_ShowOTP() {
        tab("Search")
        let field = app.searchFields.firstMatch
        guard field.waitForExistence(timeout: 6) else { return XCTFail("No search field") }
        field.tap(); field.typeText("OTP 482913\n")
        hold(4)
        mark("otp-results"); hold(6)
        tap(app.buttons["Photo"].firstMatch, "OTP photo")
        mark("otp-open"); hold(12)
    }
}
