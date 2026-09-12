import XCTest
import KeyboardCore

/// Types a long sentence as fast as XCUITest can tap on the in-app demo keyboard and checks that
/// every character arrived. Prints the on-screen key centres so the same sentence can be replayed
/// with HID-level clicks (scripts/sim_typing/fast_type_sim.py) at a rate XCUITest cannot reach.
final class FastTypingUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--reset-user-lexicon"]
        app.launch()
    }

    static let sentence = "das ist ein test und er muss jedes wort treffen auch wenn ich sehr schnell tippe"

    func testFastTapTypingTypesEveryKey() throws {
        app.tabBars.buttons["Ausprobieren"].tap()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        XCTAssertTrue(app.descendants(matching: .any)["key-q"].waitForExistence(timeout: 5), "demo keyboard not showing")
        sleep(2)   // engine load + keyboard animation

        // Resolve every key's on-screen centre once; the taps then go through coordinates only,
        // so no accessibility query sits between two keystrokes.
        var centers: [String: CGPoint] = [:]
        for id in ["q", "w", "e", "r", "t", "z", "u", "i", "o", "p", "ü", "a", "s", "d", "f", "g", "h", "j", "k", "l", "ö", "ä",
                   "y", "x", "c", "v", "b", "n", "m", "space", "backspace", "shift", "return"] {
            let el = app.descendants(matching: .any)["key-\(id)"]
            if el.exists { centers[id] = CGPoint(x: el.frame.midX, y: el.frame.midY) }
        }
        print("FAST-FRAMES app=\(app.frame) textView=\(textView.frame) tab=\(app.tabBars.buttons["Ausprobieren"].frame)")
        for (id, p) in centers.sorted(by: { $0.key < $1.key }) { print("FAST-KEY \(id) \(p.x) \(p.y)") }

        let text = Self.sentence
        let start = Date()
        for ch in text {
            let id = ch == " " ? "space" : String(ch)
            guard let p = centers[id] else { XCTFail("no key for \(id)"); return }
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y)).tap()
        }
        let elapsed = Date().timeIntervalSince(start)
        print(String(format: "FAST-RATE %.1f taps/s (%d taps in %.2fs)", Double(text.count) / elapsed, text.count, elapsed))
        sleep(1)
        let value = textView.value as? String ?? ""
        XCTAssertEqual(value.lowercased(), text.lowercased(), "typed text differs")
    }
}
