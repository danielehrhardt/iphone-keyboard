import XCTest

/// Adds the Umlaut keyboard in the simulator's Settings app (General › Keyboard › Keyboards ›
/// Add New Keyboard…). Newer simulators ignore the `AppleKeyboards` default, so run this once
/// per simulator before `ExtensionUITests`. Does nothing when Umlaut is already in the list.
final class EnableKeyboardUITests: XCTestCase {
    func testAddUmlautKeyboard() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        func tapCell(_ labels: [String]) -> Bool {
            for label in labels {
                let cell = settings.staticTexts[label].firstMatch
                if cell.waitForExistence(timeout: 2) { cell.tap(); return true }
            }
            return false
        }
        let general = settings.staticTexts["General"].firstMatch.exists ? ["General"] : ["Allgemein", "General"]
        if !tapCell(general) { settings.swipeUp(); XCTAssertTrue(tapCell(general), "no General row") }
        if !tapCell(["Keyboard", "Tastatur"]) { settings.swipeUp(); XCTAssertTrue(tapCell(["Keyboard", "Tastatur"]), "no Keyboard row") }
        let keyboards = settings.cells["KEYBOARDS"].firstMatch
        XCTAssertTrue(keyboards.waitForExistence(timeout: 3), "no Keyboards row")
        keyboards.tap()
        sleep(1)
        try? settings.debugDescription.write(toFile: "/tmp/umlaut-ui/settings-list-tree.txt", atomically: true, encoding: .utf8)
        if settings.staticTexts["Umlaut"].waitForExistence(timeout: 2) { return }
        let add = settings.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Add New Keyboard' OR label BEGINSWITH 'Neue Tastatur'")).firstMatch
        if !add.waitForExistence(timeout: 3) {
            try? settings.debugDescription.write(toFile: "/tmp/umlaut-ui/settings-tree.txt", atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(add.exists, "no Add row")
        add.tap()
        let umlaut = settings.descendants(matching: .any).matching(NSPredicate(format: "label == 'Umlaut'")).firstMatch
        for _ in 0..<6 where !umlaut.exists { settings.swipeUp() }
        if !umlaut.waitForExistence(timeout: 3) {
            try? settings.debugDescription.write(toFile: "/tmp/umlaut-ui/settings-add-tree.txt", atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(umlaut.exists, "Umlaut not offered")
        umlaut.tap()
        XCTAssertTrue(settings.staticTexts["Umlaut"].waitForExistence(timeout: 3))
    }
}
