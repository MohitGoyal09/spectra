import XCTest

/// Drives TidyRoll on a real iPhone, screen by screen, with a screenshot at every step.
/// Safety: duplicate, hide and delete run only after the viewer shows a test photo dated 1 January 2001
/// (seeded by `-uitest-seed`); Clean Up is opened but never confirmed. `test99` removes everything the run made.
@MainActor final class TidyRollUITests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    // MARK: Helpers

    private func launch(_ args: [String] = [], clearPrompts: Bool = true) {
        app.launchArguments = args
        app.launch()
        if clearPrompts { allowSystemAlerts() }
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways
        add(a)
    }

    @discardableResult
    private func tap(_ e: XCUIElement, wait: TimeInterval = 6, _ what: String = "") -> Bool {
        guard e.waitForExistence(timeout: wait), e.isHittable else {
            XCTFail("Missing: \(what.isEmpty ? e.description : what)"); return false
        }
        e.tap(); return true
    }

    private func button(_ label: String) -> XCUIElement { app.buttons[label].firstMatch }

    private func tab(_ name: String) { tap(app.tabBars.buttons[name].firstMatch, name) }

    /// Taps through permission and delete confirmations (shown by the app or by the system).
    private func allowSystemAlerts() {
        for host in [springboard, app!] {
            // Grant photo access; clear any change prompt left over from an earlier run ("Don't Allow" = no change).
            for label in ["Allow Full Access", "Allow", "OK", "Don\u{2019}t Allow", "Don't Allow"] {
                let b = host.alerts.buttons[label].firstMatch
                if b.waitForExistence(timeout: 1) { b.tap() }
            }
        }
    }

    /// Presses the button on iOS's own photo-change confirmation ("Delete", "Hide").
    private func confirm(_ label: String) {
        for host in [app!, springboard] {
            let b = host.alerts.buttons[label].firstMatch
            if b.waitForExistence(timeout: 5) { b.tap(); return }
        }
        XCTFail("No \(label) confirmation shown")
    }

    private func confirmDelete() { confirm("Delete") }

    private func search(_ text: String) {
        let field = app.searchFields.firstMatch
        if !field.exists { tab("Search") }
        guard field.waitForExistence(timeout: 6) else { return XCTFail("No search field") }
        field.tap()
        if let old = field.value as? String, !old.isEmpty, old != field.placeholderValue {
            let clear = field.buttons["Clear text"].firstMatch
            if clear.exists { clear.tap() }
        }
        field.typeText(text)
    }

    /// True only when the viewer shows a seeded test photo (dated 2001). Destructive steps check this first.
    private var onTestPhoto: Bool {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS '2001'")).firstMatch.waitForExistence(timeout: 3)
    }

    private func moreMenu(_ item: String) -> Bool {
        guard tap(button("More"), "More (⋯) menu") else { return false }
        snap("Viewer menu before \(item)")
        return tap(button(item), item)
    }

    // MARK: Flow

    func test00_SeedAndLaunch() {
        launch(["-uitest-seed", "-uitest-real-ai"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        // Wait until all 5 test items are sorted, so later tests can find them.
        search("uitest")
        let all = app.staticTexts.containing(NSPredicate(format: "label MATCHES '^[4-9] results$'")).firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 120), "Not every test item was sorted")
        snap("Library after launch")
    }

    func test01_Library() {
        launch()
        tab("Library")
        snap("Library")
        if tap(button("Filter"), "Filter") { snap("Filter menu"); app.tap() }
        let grid = app.scrollViews.firstMatch
        grid.pinch(withScale: 0.5, velocity: -1); sleep(1); snap("Grid zoomed out")
        grid.pinch(withScale: 2.0, velocity: 1); sleep(1); snap("Grid back to 3 columns")
        if tap(button("Select"), "Select") {
            let photos = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).allElementsBoundByIndex.filter(\.isHittable)
            for p in photos.prefix(2) { p.tap() }
            snap("Selecting two photos")
            if tap(button("More"), "Selection more menu") { snap("Selection menu"); app.tap() }
            tap(button("Cancel"), "Cancel selection")
        }
        if tap(button("Scan again"), "Scan again") {
            sleep(3); snap("Scan screen (globe)")
            tap(button("Close"), "Close scan")
        }
    }

    func test02_SearchWords() {
        launch()
        tab("Search")
        snap("Search empty with suggestions")
        search("uitest")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label ENDSWITH 'results'")).firstMatch.waitForExistence(timeout: 90),
                      "Test photos never showed up in search (scan of new photos)")
        sleep(2); snap("Search: uitest")
        search(" receipt")
        sleep(3); snap("Search: uitest receipt")
    }

    func test03_ViewerEverything() {
        launch()
        search("uitest")
        let first = app.buttons.matching(NSPredicate(format: "label == 'Photo'")).firstMatch
        guard tap(first, wait: 90, "first search result") else { return }
        sleep(2); snap("Viewer")
        guard onTestPhoto else { return XCTFail("Viewer did not open a 2001 test photo; stopping before any change") }

        if tap(button("Favourite"), "Favourite") { sleep(1); snap("Favourited"); tap(button("Unfavourite"), "Unfavourite") }
        if tap(button("Info"), "Info") { sleep(1); snap("Info sheet"); app.swipeDown(velocity: .fast); sleep(1) }
        if button("Live Text").waitForExistence(timeout: 3) {
            tap(button("Live Text")); sleep(3); snap("Live Text on"); tap(button("Hide Live Text"), "Hide Live Text")
        } else { XCTFail("No Live Text button") }
        let film = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Item 2 of'")).firstMatch
        if tap(film, "Filmstrip item 2") { sleep(1); snap("Filmstrip jumped to item 2") }
        app.swipeLeft(); sleep(1); snap("Swiped to next photo")

        if tap(button("Share"), "Share") {
            sleep(4); snap("Share sheet")
            // Tap above the sheet to close it (a swipe down would also close the viewer).
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
            sleep(2)
        }

        if moreMenu("Copy") { sleep(2); snap("Copied toast") }
        if moreMenu("Add to Album") {
            sleep(1); snap("Add to Album sheet")
            if tap(button("New Album…"), "New Album") {
                let field = app.alerts.textFields.firstMatch
                if field.waitForExistence(timeout: 3) { field.typeText("UITest Album"); app.alerts.buttons["Save"].tap() }
                sleep(2); snap("Added to new album")
            }
        }
        if moreMenu("Adjust Date & Time") { sleep(1); snap("Adjust date sheet"); tap(button("Cancel"), "Cancel date") }
        if moreMenu("Adjust Location") { sleep(2); snap("Adjust location sheet"); tap(button("Cancel"), "Cancel location") }
        if moreMenu("Slideshow") { sleep(5); snap("Slideshow"); tap(button("Done"), "Done slideshow"); sleep(2); snap("After slideshow Done") }

        guard onTestPhoto else { return XCTFail("Not on a test photo; skipping duplicate, hide and delete") }
        if moreMenu("Duplicate") { sleep(3); snap("Duplicated") }
        guard onTestPhoto else { return XCTFail("Not on a test photo; skipping hide and delete") }
        if moreMenu("Hide") { sleep(1); snap("Hide confirmation"); confirm("Hide"); sleep(2); snap("Hidden") }
        guard onTestPhoto else { return XCTFail("Not on a test photo; skipping delete") }
        if tap(button("Delete"), "Delete") { confirmDelete(); sleep(2); snap("Deleted") }
    }

    func test04_AskYourPhotos() {
        launch()
        search("What's the wifi password?")
        let answer = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'tea4two'")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 60), "Ask did not answer with the password")
        snap("Ask: wifi password")
    }

    func test05_PictureAndSentenceSearch() {
        launch()
        for q in ["red", "glasses", "people", "dog", "receipts from swiggy"] {
            search(q); sleep(q.contains(" ") ? 8 : 4); snap("Search: \(q)")
            app.searchFields.firstMatch.buttons["Clear text"].firstMatch.tap()
        }
    }

    func test06_Collections() {
        launch()
        tab("Collections")
        sleep(2); snap("Collections")
        app.swipeUp(); sleep(1); snap("Collections lower")
        app.swipeDown()
        if tap(button("New smart album"), "New smart album") {
            let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
            if field.waitForExistence(timeout: 3) { field.tap(); field.typeText("UITest photos with text UITEST") }
            if tap(button("Next"), "Next") {
                let match = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'photos match'")).firstMatch
                XCTAssertTrue(match.waitForExistence(timeout: 60), "Rule was not understood")
                XCTAssertFalse(app.staticTexts["0 photos match"].exists, "Smart album found no photos")
                snap("Smart album preview")
                tap(button("Save"), "Save smart album"); sleep(3)
            }
        }
        snap("Collections with new smart album")
        let suggested = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Suggested album'")).firstMatch
        if suggested.waitForExistence(timeout: 5) { snap("Suggested albums visible") }
    }

    func test07_CleanUpNoDeletes() {
        launch()
        tab("Clean Up")
        sleep(2); snap("Clean Up")
        if tap(button("Get me space"), "Get me space") { sleep(2); snap("Get me space planner"); app.swipeDown(velocity: .fast); sleep(1) }
        if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Duplicates'")).firstMatch, "Duplicates collection") {
            sleep(3); snap("Duplicates after regroup"); app.swipeUp(); sleep(2); snap("Duplicates lower")
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }
        let bucket = app.buttons.matching(NSPredicate(format: "label CONTAINS 'items,'")).firstMatch
        if tap(bucket, "a Clean Up collection") {
            sleep(2); snap("Collection grid")
            if button("Review").waitForExistence(timeout: 3) { tap(button("Review")); sleep(2); snap("Review deck"); tap(button("Close"), "Close review") }
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    func test08_PrivacyAndAIDot() {
        launch()
        tab("Library")
        let dot = app.buttons["aiStatusDot"].firstMatch
        if tap(dot, "AI status dot") {
            sleep(1); snap("AI status popover")
            if tap(button("Open privacy log"), "Open privacy log") { sleep(2); snap("Privacy log"); tap(button("Done"), "Done privacy log") }
        }
    }

    func test09_DebugTab() {
        launch()
        tab("Debug"); sleep(2); snap("Debug tab")
    }

    func test10_DarkMode() {
        launch(["-uitest-dark"])
        for t in ["Library", "Collections", "Clean Up"] { tab(t); sleep(2); snap("Dark: \(t)") }
        search("uitest"); sleep(3); snap("Dark: Search")
    }

    func test11_LightMode() {
        launch(["-uitest-light"])
        for t in ["Library", "Collections", "Clean Up"] { tab(t); sleep(2); snap("Light: \(t)") }
    }

    private func openFirstResult(_ query: String) -> Bool {
        search(query)
        let first = app.buttons.matching(NSPredicate(format: "label == 'Photo' OR label == 'Video'")).firstMatch
        return tap(first, wait: 90, "first result for \(query)")
    }

    func test12_TicketToCalendar() {
        launch()
        guard openFirstResult("uitest boarding") else { return }
        sleep(2); snap("Ticket in viewer")
        guard onTestPhoto else { return XCTFail("Not a test photo") }
        if moreMenu("Add to Calendar") {
            let cancel = app.buttons["Cancel"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 30), "Calendar editor did not open")
            sleep(1); snap("Calendar event pre-filled")
            cancel.tap()
        }
    }

    func test13_CompressVideo() {
        launch()
        guard openFirstResult("january 2001") else { return }
        // Walk to the test video in the viewer.
        for _ in 0..<6 where !button("More").exists || app.staticTexts["Saved image"].exists { app.swipeLeft(); sleep(1) }
        var found = false
        for _ in 0..<6 {
            guard tap(button("More"), "More") else { break }
            if button("Compress Video").waitForExistence(timeout: 2) { found = true; break }
            app.tap(); app.swipeLeft(); sleep(1)
        }
        guard found, onTestPhoto else { return XCTFail("Test video not found in viewer") }
        snap("Video menu with Compress")
        button("Compress Video").tap()
        confirm("Delete")
        let freed = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Freed'")).firstMatch
        XCTAssertTrue(freed.waitForExistence(timeout: 90), "No 'Freed' result after compressing")
        snap("Video compressed")
    }

    func test14_HybridDemoSwitch() {
        launch()
        tab("Library")
        guard tap(app.buttons["aiStatusDot"].firstMatch, "AI dot"), tap(button("Open privacy log"), "Open privacy log") else { return }
        let cloud = app.switches["Cloud help (masked text)"].firstMatch
        let demo = app.switches["Simulate no on-device AI"].firstMatch
        guard cloud.waitForExistence(timeout: 5) else { return XCTFail("No cloud toggle") }
        let cloudWasOn = (cloud.value as? String) == "1"
        if !cloudWasOn { cloud.switches.firstMatch.tap() }
        if (demo.value as? String) != "1" { demo.switches.firstMatch.tap() }   // set, don't toggle: a failed run may have left it on
        sleep(1); snap("Demo switch on")
        tap(button("Done"), "Done")
        search("receipts from swiggy")
        let badge = app.descendants(matching: .any)["Answered by Gemini from masked text"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 60), "Cloud fallback badge never showed")
        sleep(1); snap("Search answered by Gemini fallback")
        app.searchFields.firstMatch.typeText("\n")   // close the keyboard so the tab bar returns
        sleep(1)
        tab("Library")
        if tap(app.buttons["aiStatusDot"].firstMatch, "AI dot") { sleep(1); snap("Dot in fallback mode") ; tap(button("Open privacy log"), "Open privacy log") }
        sleep(1); snap("Privacy log with cloud request")
        if (demo.value as? String) == "1" { demo.switches.firstMatch.tap() }
        if !cloudWasOn, (cloud.value as? String) == "1" { cloud.switches.firstMatch.tap() }
        tap(button("Done"), "Done")
    }

    func test15_LargeText() {
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch(); allowSystemAlerts()
        for t in ["Library", "Collections", "Clean Up"] { tab(t); sleep(2); snap("Large text: \(t)") }
        search("uitest"); sleep(3); snap("Large text: Search")
    }

    func test16_LibrarySortAndAlbums() {
        launch()
        tab("Library")
        guard tap(button("Filter"), "Filter") else { return }
        snap("Filter menu with sort")
        if tap(button("Largest first"), "Largest first") {
            sleep(4); snap("Library largest first")
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Largest first'")).firstMatch.waitForExistence(timeout: 5))
        }
        if tap(button("Filter"), "Filter"), tap(button("Hide photos in albums"), "Hide photos in albums") {
            sleep(4); snap("Library largest first, not in an album")
        }
        // restore the defaults
        if tap(button("Filter"), "Filter") { tap(button("Hide photos in albums")) }
        if tap(button("Filter"), "Filter") { tap(button("Date")) }
        sleep(2); snap("Library back to date")
    }

    func test99_Cleanup() {
        launch(["-uitest-cleanup"], clearPrompts: false)   // the next prompts are cleanup's own deletes
        confirmDelete()
        // iOS may ask separately for albums and for photos: answer every prompt.
        for _ in 0..<3 {
            let more = [app!, springboard].map { $0.alerts.buttons["Delete"].firstMatch }.first { $0.waitForExistence(timeout: 4) }
            guard let more else { break }
            more.tap()
        }
        sleep(3); snap("After cleanup")
    }
}
