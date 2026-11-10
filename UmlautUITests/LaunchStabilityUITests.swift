import XCTest

/// A fresh install survives rotating with the demo keyboard open, right after a key popup.
final class LaunchStabilityUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private func assertRunning(_ step: String) {
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "not running after \(step)")
    }

    private func tab(_ title: String) {
        let button = app.tabBars.buttons[title].exists ? app.tabBars.buttons[title] : app.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no tab \(title)")
        button.tap()
    }

    func testRotatingWithTheDemoKeyboardOpen() {
        app.launch()
        assertRunning("launch")
        tab("Ausprobieren")
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        let key = app.descendants(matching: .any)["key-h"]
        XCTAssertTrue(key.waitForExistence(timeout: 10))
        key.tap()
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            assertRunning("rotating to \(orientation.rawValue)")
        }
        tab("Einstellungen")
        assertRunning("settings")
        tab("Start")
        assertRunning("start")
    }
}
