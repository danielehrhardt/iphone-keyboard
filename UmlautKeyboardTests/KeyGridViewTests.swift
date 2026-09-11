import XCTest
import KeyboardCore
@testable import Umlaut

/// A `UITouch` stand-in that reports a fixed location; `KeyGridView` only reads `location(in:)`.
private final class FakeTouch: UITouch {
    var point: CGPoint = .zero
    override func location(in view: UIView?) -> CGPoint { point }
}

private final class GridRecorder: KeyGridDelegate {
    var taps: [String] = []
    var alternates: [String] = []
    var swipes = 0
    var keyPreviewEnabled = true
    var swipeTypingEnabled = true
    var swipeTrailEnabled = true
    var longPressNumbersEnabled = true

    func keyGrid(_ grid: KeyGridView, didTap key: Key) { taps.append(key.id) }
    func keyGrid(_ grid: KeyGridView, didInsertAlternate text: String, for key: Key) { alternates.append(text) }
    func keyGrid(_ grid: KeyGridView, didSwipe path: [CGPoint], keyMap: KeyMap) { swipes += 1 }
    func keyGrid(_ grid: KeyGridView, didLongPress key: Key) {}
    func keyGridBackspaceRepeat(_ grid: KeyGridView, wordwise: Bool) {}
    func keyGrid(_ grid: KeyGridView, moveCursorBy offset: Int) {}
    func keyGridDidDoubleTapShift(_ grid: KeyGridView) {}
    func keyGrid(_ grid: KeyGridView, didShiftSlideTo key: Key) { taps.append(key.id) }
    func keyGrid(_ grid: KeyGridView, globeTouchEvent event: UIEvent?) {}
}

/// Drives `KeyGridView` with synthetic touches: the key preview bubble must never get in the way
/// of the next tap, whether the taps are sequential or overlap (two-thumb rollover typing).
@MainActor
final class KeyGridViewTests: XCTestCase {
    private var grid: KeyGridView!
    private var recorder: GridRecorder!
    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        let settings = KeyboardSettings(defaults: UserDefaults(suiteName: "grid-tests-\(UUID())")!)
        let theme = KeyboardTheme.current(traits: UITraitCollection(userInterfaceStyle: .light), settings: settings)
        grid = KeyGridView(theme: theme, feedback: Feedback(settings: settings))
        recorder = GridRecorder()
        grid.delegate = recorder
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        grid.frame = CGRect(x: 0, y: 44, width: 390, height: 216)
        window.addSubview(grid)
        window.isHidden = false
        grid.configure(layout: GermanLayouts.letters(), metrics: .phonePortrait)
        grid.layoutIfNeeded()
    }

    private func center(of id: String) -> CGPoint {
        grid.geometry!.keyFrames.first { $0.key.id == id }!.center
    }

    private func press(_ id: String) -> FakeTouch {
        let t = FakeTouch()
        t.point = center(of: id)
        grid.touchesBegan([t], with: nil)
        return t
    }

    private func release(_ t: FakeTouch) {
        grid.touchesEnded([t], with: nil)
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testSequentialTapsWithPreview() {
        for id in ["h", "a", "l", "l", "o"] {
            let t = press(id)
            spin(0.03)
            release(t)
            spin(0.02)
        }
        XCTAssertEqual(recorder.taps, ["h", "a", "l", "l", "o"])
    }

    func testRolloverTapsWithPreview() {
        // Second finger lands while the first is still down: both keys must be typed, in order.
        let a = press("d")
        spin(0.02)
        let b = press("a")
        release(a)
        spin(0.02)
        release(b)
        XCTAssertEqual(recorder.taps, ["d", "a"])
    }

    func testTapOnKeyUnderPreviousBubble() {
        // The bubble of "n" is drawn over "j"; a following tap on "j" must still reach "j".
        let n = press("n")
        spin(0.03)
        release(n)
        let j = press("j")
        spin(0.03)
        release(j)
        XCTAssertEqual(recorder.taps, ["n", "j"])
    }

    func testTapOnGridStillHitsGridWhilePopupVisible() {
        let n = press("n")
        spin(0.05)
        // While the bubble is up, hit testing anywhere on the grid must resolve to the grid itself.
        let hit = grid.hitTest(center(of: "j"), with: nil)
        XCTAssertTrue(hit === grid, "popup intercepted hit test: \(String(describing: hit))")
        let above = grid.hitTest(CGPoint(x: center(of: "n").x, y: center(of: "n").y - 40), with: nil)
        XCTAssertTrue(above === grid)
        release(n)
    }

    func testPreviewDisabledStillTypes() {
        recorder.keyPreviewEnabled = false
        for id in ["o", "k"] {
            let t = press(id)
            spin(0.02)
            release(t)
        }
        XCTAssertEqual(recorder.taps, ["o", "k"])
    }
}
