import XCTest
import KeyboardCore

/// Full manual-style walkthrough of the app and keyboard, saving numbered screenshots.
final class WalkthroughUITests: XCTestCase {
    let app = XCUIApplication()
    static let outDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHOT_DIR"] ?? "/tmp/umlaut-walk")

    override func setUpWithError() throws {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        app.launchArguments = ["--reset-user-lexicon"]
        app.launch()
    }

    func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: Self.outDir.appendingPathComponent("\(name).png"))
    }

    func key(_ id: String) -> XCUIElement { app.descendants(matching: .any)["key-\(id)"] }
    func tapKey(_ id: String) { key(id).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    func typeKeys(_ s: String) {
        for c in s {
            switch c {
            case " ": tapKey("space")
            case ".": tapKey(".")
            case ",": tapKey(",")
            default: tapKey(String(c))
            }
        }
    }
    func glide(_ word: String) {
        let codes = KeyAlphabet.swipeCodes(word).map { String(KeyAlphabet.character(for: $0)) }
        guard codes.count >= 2 else { return }
        let start = key(codes[0]).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // XCUITest can only drag start→end in one segment; chain via multiple press-drag calls is not
        // possible for a single touch, so glide words are limited to those whose key path is a line.
        let end = key(codes[codes.count - 1]).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: XCUIGestureVelocity.slow, thenHoldForDuration: 0.05)
    }
    var text: String { (app.textViews.firstMatch.value as? String) ?? "" }

    func testAppScreens() {
        shot("01-start")
        app.swipeUp()
        shot("02-start-scrolled")
        app.tabBars.buttons["Einstellungen"].tap()
        sleep(1)
        shot("03-settings")
        app.swipeUp()
        shot("04-settings-scrolled")
        // Switch theme to dark and accent to orange via the pickers/buttons if reachable.
        let dunkel = app.buttons["Dunkel"].firstMatch
        if dunkel.exists { dunkel.tap(); sleep(1); shot("05-settings-dark") }
        let orange = app.buttons["Orange"].firstMatch
        if orange.exists { orange.tap(); sleep(1); shot("06-settings-orange") }
        app.swipeUp()
        let learned = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Gelernte'")).firstMatch
        if learned.exists { learned.tap(); sleep(1); shot("07-learned-words") }
        // Restore defaults so later tests are deterministic.
        app.navigationBars.buttons.firstMatch.tap()
        if app.buttons["Automatisch"].firstMatch.exists { app.buttons["Automatisch"].firstMatch.tap() }
        if app.buttons["Blau"].firstMatch.exists { app.buttons["Blau"].firstMatch.tap() }
    }

    func testTypingSession() {
        app.tabBars.buttons["Ausprobieren"].tap()
        let tv = app.textViews.firstMatch
        XCTAssertTrue(tv.waitForExistence(timeout: 5))
        tv.tap()
        XCTAssertTrue(key("q").waitForExistence(timeout: 10))
        sleep(1)

        // 1. Sentence with typos, nouns, umlaut digraph and double-space period.
        typeKeys("ich habe morgen einen termin")
        shot("10-typed-raw")
        typeKeys(" ")
        shot("11-after-space")
        XCTAssertEqual(text, "Ich habe morgen einen Termin ", text)

        typeKeys("in koeln")
        shot("12-koeln-typed")
        typeKeys("  ")                              // double space → ". "
        XCTAssertEqual(text, "Ich habe morgen einen Termin in Köln. ", text)
        shot("13-koeln-fixed")

        // 2. Autocapitalisation after the period, then a typo fixed by autocorrect.
        typeKeys("dnake ")
        XCTAssertEqual(text, "Ich habe morgen einen Termin in Köln. Danke ", text)

        // 3. Backspace reverts autocorrect.
        typeKeys("hakko ")
        XCTAssertTrue(text.hasSuffix("Danke hallo "), text)          // lowercase mid-sentence
        tapKey("backspace")
        XCTAssertTrue(text.hasSuffix("Danke hakko"), text)
        shot("14-reverted")
        typeKeys(" ")

        // 4. Suggestion strip completion: tap the completion for "wochen".
        typeKeys("wochen")
        shot("15-completions")
        let completion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Vorschlag Wochenende'")).firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 2), "no Wochenende completion")
        completion.tap()
        XCTAssertTrue(text.hasSuffix("Wochenende "), text)

        // 5. Glide typing on straight paths: "du", "ja", "so", "es".
        for w in ["du", "ja", "es"] { glide(w); usleep(400_000) }
        shot("16-after-glides")
        XCTAssertTrue(text.hasSuffix("du ja es "), text)

        // 6. Shift slide: press shift, drag to "m".
        key("shift").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: key("m").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertTrue(text.hasSuffix("M"), text)

        // 7. Long-press a → alternates, slide to ä.
        let a = key("a").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        a.press(forDuration: 0.7, thenDragTo: a.withOffset(CGVector(dx: 80, dy: 0)))
        shot("17-after-longpress")
        XCTAssertTrue(text.hasSuffix("Má"), text)
        typeKeys(" ")
        XCTAssertTrue(text.hasSuffix("Má "), "deliberate accent must survive: \(text)")

        // 8. Symbols layer and back, emoji panel.
        tapKey("123")
        XCTAssertTrue(key("1").waitForExistence(timeout: 2))
        typeKeys("1")
        tapKey("#+=")
        shot("18-extra-symbols")
        tapKey("123b")
        tapKey("ABC")
        tapKey("emoji")
        sleep(1)
        shot("19-emoji")
        app.cells.firstMatch.tap()
        app.buttons["ABC"].firstMatch.tap()
        shot("20-final")
        print("WALK-FINAL-TEXT [\(text)]")

        // 9. Space-bar cursor drag moves the caret left.
        let sp = key("space").coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        sp.press(forDuration: 0.6, thenDragTo: key("space").coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        typeKeys("x")
        print("WALK-CURSOR-TEXT [\(text)]")
        XCTAssertFalse(text.hasSuffix("x"), "cursor drag did not move the caret: \(text)")
        // ~115 pt of drag at ~15 pt per step should move several characters, not one or two.
        let caretFromEnd = text.count - (text.range(of: "x").map { text.distance(from: text.startIndex, to: $0.lowerBound) } ?? text.count)
        XCTAssertGreaterThanOrEqual(caretFromEnd, 5, "moved only \(caretFromEnd - 1) characters: \(text)")
        shot("21-cursor")
    }
}
