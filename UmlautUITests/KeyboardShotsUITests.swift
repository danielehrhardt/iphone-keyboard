import XCTest
import KeyboardCore

/// Screenshots of the demo keyboard's strip and keys with two languages and the assistant on,
/// for reviewing the chrome in light and dark mode (switch with `xcrun simctl ui <sim> appearance`).
/// Saved under /tmp/umlaut-ui (or $SHOT_DIR).
final class KeyboardShotsUITests: XCTestCase {
    let app = XCUIApplication()
    static let outDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHOT_DIR"] ?? "/tmp/umlaut-ui")

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        app.launchArguments = ["--reset-user-lexicon"]
        app.launch()
    }

    func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: Self.outDir.appendingPathComponent("\(name).png"))
    }

    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func switchOn(_ toggle: XCUIElement) {
        guard (toggle.value as? String) != "1" else { return }
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }

    func testStripAndKeys() throws {
        app.tabBars.buttons["Einstellungen"].tap()
        let english = element("language-en")
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        switchOn(english)
        element("ai-settings").tap()
        let ai = app.switches["ai-enabled"]
        XCTAssertTrue(ai.waitForExistence(timeout: 5))
        switchOn(ai)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["Ausprobieren"].tap()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        XCTAssertTrue(element("key-q").waitForExistence(timeout: 5), "demo keyboard not showing")
        sleep(1)
        shot("strip-01-empty")
        for id in ["key-h", "key-a", "key-l", "key-l", "key-o", "key-space", "key-w", "key-i", "key-e"] {
            element(id).tap()
        }
        sleep(1)
        shot("strip-02-typing")
        element("key-space").tap()
        sleep(1)
        shot("strip-03-predictions")

        element("key-123").tap()
        sleep(1)
        shot("strip-04-symbols")
        element("key-ABC").tap()

        element("ai-button").tap()
        XCTAssertTrue(element("ai-panel").waitForExistence(timeout: 3))
        sleep(1)
        shot("strip-05-ai-panel")
        element("ai-letters").tap()
        XCTAssertTrue(element("key-q").waitForExistence(timeout: 3))

        element("keyboard-clipboard").tap()
        XCTAssertTrue(element("clipboard-letters").waitForExistence(timeout: 3))
        sleep(1)
        shot("strip-06-clipboard")
        element("clipboard-letters").tap()
        XCTAssertTrue(element("key-q").waitForExistence(timeout: 3))

        element("key-comma").press(forDuration: 0.8)
        sleep(1)
        shot("strip-07-emoji")
    }
}
