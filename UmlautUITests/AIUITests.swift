import XCTest
import KeyboardCore

/// Walks through the AI setup in the app and opens the AI panel on the demo keyboard, saving
/// screenshots under /tmp/umlaut-ui. Uses a fake key, so the request itself ends in the panel's
/// error state – which is the state under test here, not a provider's answer.
final class AIUITests: XCTestCase {
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

    func keyPoint(_ label: String, layout: KeyboardLayout, keyboardFrame: CGRect, suggestionHeight: CGFloat) -> XCUICoordinate {
        let gridSize = CGSize(width: keyboardFrame.width, height: keyboardFrame.height - suggestionHeight)
        let g = KeyboardGeometry(layout: layout, size: gridSize, metrics: .phonePortrait)
        let kf = g.keyFrames.first { $0.key.label == label || $0.key.id == label }!
        let p = CGPoint(x: keyboardFrame.minX + kf.center.x, y: keyboardFrame.minY + suggestionHeight + kf.center.y)
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y))
    }

    func gridFrame(layout: KeyboardLayout, heights: (keys: CGFloat, suggestions: CGFloat)) -> CGRect {
        let q = element("key-q")
        XCTAssertTrue(q.waitForExistence(timeout: 5), "demo keyboard not showing")
        let width = app.frame.width
        let g = KeyboardGeometry(layout: layout, size: CGSize(width: width, height: heights.keys), metrics: .phonePortrait)
        let qf = g.keyFrame(for: g.keyFrames.first { $0.key.id == "q" }!.key)!.frame
        let originY = q.frame.midY - qf.midY - heights.suggestions
        return CGRect(x: 0, y: originY, width: width, height: heights.keys + heights.suggestions)
    }

    func testSetupAndPanel() throws {
        // Settings › KI
        app.tabBars.buttons["Einstellungen"].tap()
        let row = element("ai-settings")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let toggle = app.switches["ai-enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        shot("ai-01-settings")
        if (toggle.value as? String) != "1" { toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap() }

        // Anthropic key from the pasteboard (filled by the runner with `simctl pbcopy`).
        element("ai-provider-anthropic").tap()
        let paste = app.buttons["Aus der Zwischenablage einfügen"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        shot("ai-02-provider-key")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)
        shot("ai-03-configured")
        XCTAssertTrue(app.staticTexts["Claude Opus 5"].waitForExistence(timeout: 5), "first key picks the provider's default model")

        app.swipeUp()
        let modelRow = element("ai-default-model")
        XCTAssertTrue(modelRow.waitForExistence(timeout: 5))
        modelRow.tap()
        XCTAssertTrue(app.staticTexts["gpt-5.6-sol"].waitForExistence(timeout: 5))
        shot("ai-04-model-picker")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Playground: type, open the panel, run a feature (fails with the fake key).
        app.tabBars.buttons["Ausprobieren"].tap()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        sleep(2)
        let heights = (keys: CGFloat(216), suggestions: CGFloat(44))
        let letters = GermanLayouts.letters(options: LayoutOptions(needsGlobeKey: false, showsEmojiKey: true, isEmailOrURL: false))
        let kb = gridFrame(layout: letters, heights: heights)
        func tap(_ k: String) { keyPoint(k, layout: letters, keyboardFrame: kb, suggestionHeight: heights.suggestions).tap() }
        for k in ["h", "a", "l", "l", "o", "space", "w", "e", "l", "t"] { tap(k) }
        sleep(1)
        shot("ai-05-strip-with-button")

        let aiButton = element("ai-button")
        XCTAssertTrue(aiButton.waitForExistence(timeout: 3), "✦ button in the strip")
        aiButton.tap()
        XCTAssertTrue(element("ai-panel").waitForExistence(timeout: 3))
        sleep(1)
        shot("ai-06-panel-idle")

        element("ai-feature-rewrite").tap()
        sleep(1)
        shot("ai-07-panel-loading-or-result")
        // The fake key is rejected by the provider; the panel shows the error card.
        XCTAssertTrue(app.staticTexts["Der API-Schlüssel wurde abgelehnt."].waitForExistence(timeout: 20)
                      || app.staticTexts["Keine Verbindung."].exists)
        shot("ai-08-panel-error")

        element("ai-feature-translate").tap()
        sleep(1)
        shot("ai-09-panel-translate-chips")
        element("ai-letters").tap()
        XCTAssertTrue(element("key-q").waitForExistence(timeout: 3), "back to the letters")
        shot("ai-10-back-to-keys")
    }
}
