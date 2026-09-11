import XCTest
import KeyboardCore

/// Exercises the real keyboard extension (enabled on the simulator via the AppleKeyboards default)
/// inside the host app with the in-app demo switched off.
final class ExtensionUITests: XCTestCase {
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

    /// Long-presses the system globe key and picks "Umlaut" from the keyboard list.
    func switchToUmlaut() {
        let globe = app.buttons["Nächste Tastatur"]
        guard globe.waitForExistence(timeout: 3) else { return }   // already on a third-party keyboard
        globe.press(forDuration: 1.2)
        let item = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Umlaut'")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), "Umlaut not in the keyboard list")
        item.tap()
        sleep(2)
    }

    func testExtensionAppearsAndTypes() throws {
        app.tabBars.buttons["Ausprobieren"].tap()
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) == "1" { toggle.tap() }
        let textView = app.textViews.firstMatch
        textView.tap()
        sleep(2)
        switchToUmlaut()
        shot("11-extension")
        XCTAssertTrue(app.descendants(matching: .any)["key-q"].waitForExistence(timeout: 10), "Umlaut keyboard not showing")
        // Predictions appear once the engine has loaded.
        let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Vorschlag'")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 15), "no suggestions – engine did not load?")
        shot("11b-extension-loaded")
        XCTAssertFalse(app.buttons["shift"].exists, "system keyboard still showing")

        // Keys are accessibility elements ("key-<id>"), so they can be addressed directly.
        func key(_ id: String) -> XCUIElement { app.descendants(matching: .any)["key-\(id)"] }
        XCTAssertTrue(key("d").waitForExistence(timeout: 3), "Umlaut keys not found")
        print("EXT-KB-FRAME \(key("q").frame) … \(key("return").frame)")
        func point(_ id: String) -> XCUICoordinate { key(id).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)) }
        for k in ["d", "a", "n", "k", "e", "space"] { point(k).tap() }
        sleep(1)
        shot("12-extension-typed")
        let value = textView.value as? String ?? ""
        XCTAssertEqual(value, "Danke ", "got \(value)")

        point("d").press(forDuration: 0.05, thenDragTo: point("u"), withVelocity: XCUIGestureVelocity.slow, thenHoldForDuration: 0.05)
        sleep(1)
        shot("13-extension-swiped")
        let value2 = textView.value as? String ?? ""
        XCTAssertEqual(value2, "Danke du ", "got \(value2)")
    }
}
