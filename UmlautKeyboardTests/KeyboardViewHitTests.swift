import XCTest
import KeyboardCore
@testable import Umlaut

private final class FakeTouch: UITouch {
    var point: CGPoint = .zero
    override func location(in view: UIView?) -> CGPoint { point }
}

private final class Recorder: KeyGridDelegate {
    var taps: [String] = []
    var keyPreviewEnabled = true
    var swipeTypingEnabled = true
    var swipeTrailEnabled = true
    var longPressNumbersEnabled = true
    func keyGrid(_ grid: KeyGridView, didTap key: Key) { taps.append(key.id) }
    func keyGrid(_ grid: KeyGridView, didInsertAlternate text: String, for key: Key) {}
    func keyGrid(_ grid: KeyGridView, didSwipe path: [CGPoint], keyMap: KeyMap) {}
    func keyGrid(_ grid: KeyGridView, didLongPress key: Key) {}
    func keyGridBackspaceRepeat(_ grid: KeyGridView, wordwise: Bool) {}
    func keyGrid(_ grid: KeyGridView, moveCursorBy offset: Int) {}
    func keyGridDidDoubleTapShift(_ grid: KeyGridView) {}
    func keyGrid(_ grid: KeyGridView, didShiftSlideTo key: Key) {}
    func keyGrid(_ grid: KeyGridView, globeTouchEvent event: UIEvent?) {}
}

/// On a phone with a home indicator the keyboard is taller than its keys: a strip the height of
/// the bottom safe-area inset sits below the last row. A fast thumb lands in that strip all the
/// time, so it must belong to the nearest key rather than swallow the tap.
@MainActor
final class KeyboardViewHitTests: XCTestCase {
    private var view: KeyboardView!
    private var recorder: Recorder!
    private var window: UIWindow!
    private let suggestions: CGFloat = 44
    private let keys: CGFloat = 216
    private let bottomInset: CGFloat = 34

    override func setUp() {
        super.setUp()
        let settings = KeyboardSettings(defaults: UserDefaults(suiteName: "kbview-tests-\(UUID())")!)
        let theme = KeyboardTheme.current(traits: UITraitCollection(userInterfaceStyle: .light), settings: settings)
        view = KeyboardView(theme: theme, feedback: Feedback(settings: settings))
        recorder = Recorder()
        view.grid.delegate = recorder
        view.suggestionHeight = suggestions
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        // Same shape the extension gets: keys + strip, laid out with the strip left free below the grid.
        view.frame = CGRect(x: 0, y: 0, width: 390, height: suggestions + keys + bottomInset)
        view.onLayout = { [unowned self] in
            self.view.grid.configure(layout: GermanLayouts.letters(), metrics: .phonePortrait)
        }
        window.addSubview(view)
        window.isHidden = false
        view.layoutIfNeeded()
        // `layoutSubviews` only knows the real safe area inside a window; force the split here.
        view.grid.frame = CGRect(x: 0, y: suggestions, width: 390, height: keys)
        view.grid.configure(layout: GermanLayouts.letters(), metrics: .phonePortrait)
    }

    private func tap(at point: CGPoint) {
        let hit = view.hitTest(point, with: nil)
        XCTAssertTrue(hit === view.grid, "expected the grid at \(point), got \(String(describing: hit))")
        let t = FakeTouch()
        t.point = view.convert(point, to: view.grid)
        view.grid.touchesBegan([t], with: nil)
        view.grid.touchesEnded([t], with: nil)
    }

    func testStripBelowTheKeysBelongsToTheBottomRow() {
        let spaceX = view.grid.geometry!.keyFrames.first { $0.key.id == "space" }!.center.x
        tap(at: CGPoint(x: spaceX, y: suggestions + keys + bottomInset - 2))   // 2 pt above the screen edge
        tap(at: CGPoint(x: spaceX, y: suggestions + keys + 1))                 // just below the grid
        XCTAssertEqual(recorder.taps, ["space", "space"])
    }

    func testStripCornersGoToTheNearestKey() {
        let rowY = suggestions + keys + 10
        tap(at: CGPoint(x: 8, y: rowY))
        tap(at: CGPoint(x: 382, y: rowY))
        let bottom = view.grid.geometry!.layout.rows.last!.keys
        XCTAssertEqual(recorder.taps, [bottom.first!.id, bottom.last!.id])
    }

    func testSuggestionBarKeepsItsTouches() {
        let hit = view.hitTest(CGPoint(x: 195, y: suggestions / 2), with: nil)
        XCTAssertFalse(hit === view.grid, "a tap on the suggestion strip must not type a key")
    }

    func testEmojiPanelCoversTheStrip() {
        view.emojiDelegate = nil
        view.isEmojiVisible = true
        let hit = view.hitTest(CGPoint(x: 195, y: suggestions + keys + 10), with: nil)
        XCTAssertFalse(hit === view.grid)
        XCTAssertTrue(hit?.isDescendant(of: view.emojiPanel!) ?? false)
    }
}
