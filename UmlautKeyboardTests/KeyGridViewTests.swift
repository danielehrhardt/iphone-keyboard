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
    var longPresses: [String] = []
    var swipes = 0
    var keyPreviewEnabled = true
    var swipeTypingEnabled = true
    var swipeTrailEnabled = true
    var longPressNumbersEnabled = true

    func keyGrid(_ grid: KeyGridView, didTap key: Key) { taps.append(key.id) }
    func keyGrid(_ grid: KeyGridView, didInsertAlternate text: String, for key: Key) { alternates.append(text) }
    func keyGrid(_ grid: KeyGridView, didSwipe path: [CGPoint], keyMap: KeyMap) { swipes += 1 }
    func keyGrid(_ grid: KeyGridView, didLongPress key: Key) { longPresses.append(key.id) }
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

    /// The alternates bubble is laid out so the option nearest the key sits directly over it —
    /// that alignment is what lets the stem grow straight out of the key instead of drawing a
    /// notched, cut-off bubble. It also has to agree with the bubble's hit regions, so the option
    /// under the finger is the one that gets committed.
    func testAlternatesRowLinesUpWithTheKey() {
        let kf = grid.geometry!.keyFrames.first { $0.key.id == "w" }!
        let optionWidth = max(kf.frame.width * 1.1, 38)
        // "w" is on the left half, so the row grows rightwards from the key: ["2", "w"].
        for (step, expected) in [(0 as CGFloat, "2"), (optionWidth, "w")] {
            recorder.alternates = []
            let t = press("w")
            spin(0.5)
            t.point = CGPoint(x: kf.center.x + step, y: kf.center.y)
            grid.touchesMoved([t], with: nil)
            release(t)
            spin(0.02)
            XCTAssertEqual(recorder.alternates, [expected], "option \(step)pt right of the key centre")
        }
    }

    /// The comma key doubles as the emoji key: a tap types the comma, a hold reports the long
    /// press (the coordinator opens the emoji panel) and the following lift must not type anything.
    func testHoldingCommaKeyFiresLongPressInsteadOfTyping() {
        let hold = press("comma")
        spin(0.5)
        XCTAssertEqual(recorder.longPresses, ["comma"])
        release(hold)
        spin(0.02)
        XCTAssertEqual(recorder.taps, [], "the hold swallowed the tap")
        XCTAssertEqual(recorder.alternates, [], "no ; : bubble on the combined key")

        let tap = press("comma")
        spin(0.03)
        release(tap)
        XCTAssertEqual(recorder.taps, ["comma"])
        XCTAssertEqual(recorder.longPresses, ["comma"])
    }

    /// With the keys separated the comma key keeps its ; : bubble and never reports a long press.
    func testSeparateCommaKeyKeepsAlternates() {
        grid.configure(layout: GermanLayouts.letters(options: LayoutOptions(emojiOnCommaKey: false)), metrics: .phonePortrait)
        grid.layoutIfNeeded()
        let t = press("comma")
        spin(0.5)
        release(t)
        spin(0.02)
        XCTAssertEqual(recorder.longPresses, [])
        XCTAssertEqual(recorder.alternates, [","], "bubble committed the option under the finger")
    }

    // MARK: Fast typing

    /// Thirty taps with no run-loop turn in between (what a stalled main thread sees when it
    /// catches up): every one of them is typed, in order.
    func testBurstOfTapsIsNeverDropped() {
        let ids = Array(repeating: ["d", "a", "s", "i", "s", "t", "e", "i", "n", "t"], count: 3).flatMap { $0 }
        for id in ids {
            let t = press(id)
            release(t)
        }
        XCTAssertEqual(recorder.taps, ids)
        XCTAssertEqual(recorder.swipes, 0)
    }

    /// A quick tap that drifts a little is still a tap on the key under the finger, never a
    /// glide the decoder has to guess a word for.
    func testSloppyTapStaysATap() {
        let e = center(of: "e")
        let t = press("e")
        t.point = CGPoint(x: e.x + 14, y: e.y + 3)
        grid.touchesMoved([t], with: nil)
        release(t)
        XCTAssertEqual(recorder.taps, ["e"])
        XCTAssertEqual(recorder.swipes, 0)

        // Further into the neighbour: the key under the finger wins (system behaviour).
        let u = press("e")
        u.point = CGPoint(x: e.x + 22, y: e.y)
        grid.touchesMoved([u], with: nil)
        release(u)
        XCTAssertEqual(recorder.taps, ["e", "r"])
        XCTAssertEqual(recorder.swipes, 0)

        // Real travel is a glide.
        let g = press("e")
        for i in 1...6 { g.point = CGPoint(x: e.x + CGFloat(i) * 14, y: e.y); grid.touchesMoved([g], with: nil) }
        release(g)
        XCTAssertEqual(recorder.taps, ["e", "r"])
        XCTAssertEqual(recorder.swipes, 1)
    }

    /// The other thumb keeps typing while a glide is in flight.
    func testTapWhileAnotherFingerGlidesIsTyped() {
        let a = center(of: "a")
        let glide = press("a")
        for i in 1...6 { glide.point = CGPoint(x: a.x + CGFloat(i) * 14, y: a.y); grid.touchesMoved([glide], with: nil) }
        let tap = press("l")
        release(tap)
        XCTAssertEqual(recorder.taps, ["l"])
        release(glide)
        XCTAssertEqual(recorder.swipes, 1)
    }

    /// When the main thread stalls, the long-press timer can fire before the lift that is
    /// queued behind it. That must not turn a tap on "e" into its alternates bubble (whose first
    /// option is the digit 3).
    func testOverdueLongPressTimerLeavesAQuickTapAlone() {
        let t = press("e")
        Thread.sleep(forTimeInterval: KeyGridView.longPressDelay + 0.5)   // the stall
        spin(0.02)                                                       // the overdue timer fires
        release(t)
        XCTAssertEqual(recorder.taps, ["e"])
        XCTAssertEqual(recorder.alternates, [])
        XCTAssertEqual(recorder.longPresses, [])
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

/// The popup is drawn as one bubble-plus-stem outline. The stem's shoulders flare outwards into
/// the bubble's bottom edge, so they have to sit inside the straight part of that edge: when a
/// shoulder was allowed past a rounded corner the outline doubled back on itself and the bubble
/// rendered with a notch cut out of it.
@MainActor
final class KeyPopupShapeTests: XCTestCase {
    private func makePopup() -> KeyPopupView {
        let settings = KeyboardSettings(defaults: UserDefaults(suiteName: "popup-tests-\(UUID())")!)
        let theme = KeyboardTheme.current(traits: UITraitCollection(userInterfaceStyle: .dark), settings: settings)
        let popup = KeyPopupView(theme: theme)
        popup.frame = CGRect(x: 0, y: 0, width: 390, height: 216)
        return popup
    }

    /// Walks the outline and returns the x of every point it puts on the bubble's bottom edge,
    /// in path order. The path runs along that edge right-to-left, so x must never increase.
    private func bottomEdgeXs(of popup: KeyPopupView) -> [CGFloat] {
        guard let path = popup.outlinePath else { return [] }
        let y = popup.stemTop
        var xs: [CGFloat] = []
        path.applyWithBlock { element in
            let e = element.pointee
            let count: Int
            switch e.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            for i in 0..<count where abs(e.points[i].y - y) < 0.001 {
                xs.append(e.points[i].x)
            }
        }
        return xs
    }

    private func assertOutlineIsWellFormed(_ popup: KeyPopupView, _ label: String,
                                           file: StaticString = #filePath, line: UInt = #line) {
        let xs = bottomEdgeXs(of: popup)
        XCTAssertGreaterThanOrEqual(xs.count, 4, "\(label): expected shoulders on the bottom edge", file: file, line: line)
        for (a, b) in zip(xs, xs.dropFirst()) {
            XCTAssertLessThanOrEqual(b, a + 0.001,
                                     "\(label): outline doubles back along the bottom edge (\(xs))",
                                     file: file, line: line)
        }
    }

    func testAlternatesOutlineDoesNotDoubleBack() {
        let container = CGRect(x: 0, y: 0, width: 390, height: 216)
        // A narrow key at the left edge is the tight case: the bubble barely overhangs the key.
        let key = CGRect(x: 3, y: 60, width: 32, height: 42)
        let popup = makePopup()
        popup.showAlternates(["2", "w"], keyFrame: key, in: container, preferLeft: false)
        assertOutlineIsWellFormed(popup, "alternates growing right")

        let rightKey = CGRect(x: container.maxX - 35, y: 60, width: 32, height: 42)
        popup.showAlternates(["0", "p"], keyFrame: rightKey, in: container, preferLeft: true)
        assertOutlineIsWellFormed(popup, "alternates growing left")

        // A wide key (space) with a single narrow bubble is the opposite extreme.
        let wide = CGRect(x: 80, y: 160, width: 200, height: 42)
        popup.showAlternates(["a", "b", "c"], keyFrame: wide, in: container, preferLeft: false)
        assertOutlineIsWellFormed(popup, "alternates on a wide key")
    }

    func testPreviewOutlineDoesNotDoubleBack() {
        let container = CGRect(x: 0, y: 0, width: 390, height: 216)
        for x in [CGFloat(0), 3, 180, 355, 358] {
            let popup = makePopup()
            popup.showPreview(text: "w", keyFrame: CGRect(x: x, y: 60, width: 32, height: 42), in: container)
            assertOutlineIsWellFormed(popup, "preview at x=\(x)")
        }
    }
}
