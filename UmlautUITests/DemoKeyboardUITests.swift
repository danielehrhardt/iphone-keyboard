import XCTest
import KeyboardCore

/// Drives the in-app demo keyboard end to end and saves screenshots under /tmp/umlaut-ui.
final class DemoKeyboardUITests: XCTestCase {
    let app = XCUIApplication()
    static let outDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHOT_DIR"] ?? "/tmp/umlaut-ui")

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        app.launchArguments = ["--reset-user-lexicon"]
        app.launch()
    }

    func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: Self.outDir.appendingPathComponent("\(name).png"))
    }

    /// Screen-point coordinate of a key on the demo keyboard. `keyboardFrame` is the key grid's
    /// frame on screen (see `gridFrame`), so the maths stays right whether or not the keyboard
    /// grows by the home-indicator safe area.
    func keyPoint(_ label: String, layout: KeyboardLayout, keyboardFrame: CGRect, suggestionHeight: CGFloat) -> XCUICoordinate {
        let gridSize = CGSize(width: keyboardFrame.width, height: keyboardFrame.height - suggestionHeight)
        let g = KeyboardGeometry(layout: layout, size: gridSize, metrics: .phonePortrait)
        let kf = g.keyFrames.first { $0.key.label == label || $0.key.id == label }!
        let p = CGPoint(x: keyboardFrame.minX + kf.center.x, y: keyboardFrame.minY + suggestionHeight + kf.center.y)
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y))
    }

    /// Suggestion bar + key grid frame on screen, derived from where the real "q" key cap is.
    func gridFrame(layout: KeyboardLayout, heights: (keys: CGFloat, suggestions: CGFloat)) -> CGRect {
        let q = app.descendants(matching: .any)["key-q"]
        XCTAssertTrue(q.waitForExistence(timeout: 5), "demo keyboard not showing")
        let width = app.frame.width
        let g = KeyboardGeometry(layout: layout, size: CGSize(width: width, height: heights.keys), metrics: .phonePortrait)
        let qf = g.keyFrame(for: g.keyFrames.first { $0.key.id == "q" }!.key)!.frame
        let originY = q.frame.midY - qf.midY - heights.suggestions
        return CGRect(x: 0, y: originY, width: width, height: heights.keys + heights.suggestions)
    }

    func testTypeCorrectAndSwipe() throws {
        app.tabBars.buttons["Ausprobieren"].tap()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        sleep(2)   // engine load + keyboard animation
        shot("01-keyboard")

        // Mirrors KeyboardMetrics for a tall phone in portrait (216 pt keys + 44 pt suggestion strip);
        // the grid's position comes from the live "q" key so the safe-area strip below doesn't matter.
        let heights = (keys: CGFloat(216), suggestions: CGFloat(44))
        let letters = GermanLayouts.letters(options: LayoutOptions(needsGlobeKey: false, showsEmojiKey: true, isEmailOrURL: false))
        let kb = gridFrame(layout: letters, heights: heights)

        func tap(_ k: String) { keyPoint(k, layout: letters, keyboardFrame: kb, suggestionHeight: heights.suggestions).tap() }

        // Tap typing with a typo: "hakko " → "Hallo "
        for k in ["h", "a", "k", "k", "o"] { tap(k) }
        shot("02-typed-hakko")
        tap("space")
        sleep(1)
        shot("03-autocorrected")
        let value = textView.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("Hallo "), "got \(value)")

        // Long-press on "a" shows alternates; capture while the finger is still down.
        let popupShot = DispatchWorkItem { self.shot("04-longpress") }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.9, execute: popupShot)
        keyPoint("a", layout: letters, keyboardFrame: kb, suggestionHeight: heights.suggestions).press(forDuration: 1.6)
        popupShot.wait()

        // Glide "du": straight drag from d to u.
        let d = keyPoint("d", layout: letters, keyboardFrame: kb, suggestionHeight: heights.suggestions)
        let u = keyPoint("u", layout: letters, keyboardFrame: kb, suggestionHeight: heights.suggestions)
        d.press(forDuration: 0.05, thenDragTo: u, withVelocity: XCUIGestureVelocity.slow, thenHoldForDuration: 0.05)
        sleep(1)
        shot("05-after-swipe")
        let value2 = textView.value as? String ?? ""
        XCTAssertTrue(value2.lowercased().contains(" du "), "got \(value2)")

        // Symbols layer + emoji panel.
        tap("123")
        sleep(1)
        shot("06-symbols")
        let symbols = GermanLayouts.symbols(options: LayoutOptions(needsGlobeKey: false))
        keyPoint("ABC", layout: symbols, keyboardFrame: kb, suggestionHeight: heights.suggestions).tap()
        tap("emoji")
        sleep(1)
        shot("07-emoji")
    }

    /// The keyboard can be closed from its own dismiss button and by tapping outside the editor.
    func testDismissKeyboard() throws {
        app.tabBars.buttons["Ausprobieren"].tap()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))

        let dismiss = app.buttons["dismiss-keyboard"]
        textView.tap()
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5), "dismiss button should be in the suggestion bar")
        shot("08-dismiss-button")
        dismiss.tap()
        XCTAssertTrue(waitUntilGone(dismiss), "keyboard should hide after tapping the dismiss button")
        shot("09-dismissed-by-button")

        textView.tap()
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        app.staticTexts["Wischen"].tap()   // a tip card, outside the editor
        XCTAssertTrue(waitUntilGone(dismiss), "keyboard should hide after tapping outside the editor")
        shot("10-dismissed-by-tap-outside")
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: element)], timeout: timeout) == .completed
    }
}
