import XCTest

/// Copies text on the simulator, opens the clipboard history from the keyboard's "⋯" menu and
/// types the entry back into the demo text view. Screenshots go to /tmp/umlaut-ui.
final class ClipboardUITests: XCTestCase {
    let app = XCUIApplication()
    static let outDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHOT_DIR"] ?? "/tmp/umlaut-ui")

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        // Reading a clip another process wrote makes iOS ask for permission; allow it.
        addUIInterruptionMonitor(withDescription: "paste permission") { alert in
            for label in ["Allow Paste", "Einsetzen erlauben", "Erlauben", "Allow"] {
                let b = alert.buttons[label]
                if b.exists { b.tap(); return true }
            }
            return false
        }
        app.launch()
    }

    func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: Self.outDir.appendingPathComponent("\(name).png"))
    }

    func testCopiedTextShowsUpInTheKeyboardAndCanBeReinserted() throws {
        let clip = "Zwischenablage \(Int(Date().timeIntervalSince1970) % 10_000)"
        UIPasteboard.general.string = clip

        app.tabBars.buttons["Ausprobieren"].tap()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        let actions = app.descendants(matching: .any)["keyboard-actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5), "no ⋯ button on the suggestion strip")
        actions.tap()
        let clipboardRow = app.descendants(matching: .any)["action-clipboard"]
        XCTAssertTrue(clipboardRow.waitForExistence(timeout: 3), "action menu did not open")
        shot("20-action-menu")
        clipboardRow.tap()
        sleep(1)
        shot("21-after-clipboard-tap")
        app.tap()   // lets a pending permission alert reach the interruption monitor
        // The "ABC" button is the panel's one element that is always an accessibility element.
        let panel = app.descendants(matching: .any)["clipboard-letters"]
        XCTAssertTrue(panel.waitForExistence(timeout: 3), "clipboard panel did not open")
        let entry = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", clip)).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "copied text not listed")
        shot("22-clipboard-panel")
        entry.tap()
        sleep(1)
        shot("23-reinserted")
        let value = textView.value as? String ?? ""
        XCTAssertTrue(value.contains(clip), "got \(value)")
        XCTAssertTrue(app.descendants(matching: .any)["key-q"].waitForExistence(timeout: 3), "keys not back after picking an entry")
    }
}
