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

    /// Screen-point coordinate of a key on the demo keyboard (keyboard is bottom-aligned).
    func keyPoint(_ label: String, layout: KeyboardLayout, keyboardFrame: CGRect, suggestionHeight: CGFloat) -> XCUICoordinate {
        let gridSize = CGSize(width: keyboardFrame.width, height: keyboardFrame.height - suggestionHeight)
        let g = KeyboardGeometry(layout: layout, size: gridSize, metrics: .phonePortrait)
        let kf = g.keyFrames.first { $0.key.label == label || $0.key.id == label }!
        let p = CGPoint(x: keyboardFrame.minX + kf.center.x, y: keyboardFrame.minY + suggestionHeight + kf.center.y)
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y))
    }

    func testTypeCorrectAndSwipe() throws {
        app.tabBars.buttons["Ausprobieren"].tap()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        sleep(2)   // engine load + keyboard animation
        shot("01-keyboard")

        // The demo keyboard is the input view: bottom of the screen, height from KeyboardMetrics.
        let screen = app.frame
        // Mirrors KeyboardMetrics for a tall phone in portrait (216 pt keys + 44 pt suggestion strip).
        let heights = (keys: CGFloat(216), suggestions: CGFloat(44))
        let total = heights.keys + heights.suggestions
        let kb = CGRect(x: 0, y: screen.height - total, width: screen.width, height: total)
        let letters = GermanLayouts.letters(options: LayoutOptions(needsGlobeKey: false, showsEmojiKey: true, isEmailOrURL: false))

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
}
