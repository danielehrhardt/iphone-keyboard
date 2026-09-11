import XCTest

/// Captures App Store screenshots on whatever device the test runs on. Everything is driven through
/// accessibility identifiers and element frames, so no layout maths has to be kept in sync here.
final class AppStoreShotsUITests: XCTestCase {
    let app = XCUIApplication()
    static let outDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHOT_DIR"] ?? "/tmp/umlaut-shots")

    override func setUpWithError() throws {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        app.launchArguments = ["--reset-user-lexicon"]
        app.launch()
    }

    func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: Self.outDir.appendingPathComponent("\(name).png"))
    }

    func key(_ id: String) -> XCUIElement { app.descendants(matching: .any)["key-\(id)"] }

    /// iPad renders the TabView as a floating bar rather than a UITabBar, so fall back to any
    /// button carrying the tab's title.
    func tab(_ title: String) -> XCUIElement {
        let inTabBar = app.tabBars.buttons[title]
        if inTabBar.exists { return inTabBar }
        return app.buttons[title].firstMatch
    }

    func tap(_ ids: [String]) {
        for id in ids {
            let k = key(id)
            if k.waitForExistence(timeout: 3) { k.tap() }
        }
    }

    /// Glide from key to key with a single continuous drag.
    func swipe(_ ids: [String]) {
        let points = ids.compactMap { id -> XCUICoordinate? in
            let k = key(id)
            guard k.exists else { return nil }
            return k.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        }
        guard points.count > 1 else { return }
        points[0].press(forDuration: 0.05, thenDragTo: points[1], withVelocity: .default, thenHoldForDuration: 0.01)
        // A single press/drag pair only gives a straight line; walk the remaining keys as a chain.
        for i in 1..<(points.count - 1) {
            points[i].press(forDuration: 0.01, thenDragTo: points[i + 1], withVelocity: .default, thenHoldForDuration: 0.01)
        }
    }

    func testCaptureStoreScreenshots() throws {
        // 1 – Start / onboarding
        XCTAssertTrue(tab("Start").waitForExistence(timeout: 15))
        sleep(1)
        shot("01-start")

        // 2 – the demo keyboard
        tab("Ausprobieren").tap()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        textView.tap()
        sleep(3)   // engine load + keyboard animation
        shot("02-keyboard")

        // 3 – typing with a typo that autocorrect fixes, so the suggestion bar has content
        tap(["h", "a", "k", "k", "o"])
        sleep(1)
        shot("03-autocorrect")
        tap(["space"])
        tap(["w", "e", "l", "t"])
        sleep(1)
        shot("04-suggestions")

        // 4 – emoji panel
        let emoji = key("emoji")
        if emoji.waitForExistence(timeout: 3) {
            emoji.tap()
            sleep(2)
            shot("05-emoji")
            let abc = key("abc")
            if abc.exists { abc.tap() }
        }

        // 5 – settings
        tab("Einstellungen").tap()
        sleep(2)
        shot("06-settings")

        // 6 – learned words / tap map detail screens
        let tapMap = app.buttons["Deine Tap Map"].firstMatch
        if tapMap.waitForExistence(timeout: 3) {
            tapMap.tap()
            sleep(2)
            shot("07-tapmap")
        }
    }
}
