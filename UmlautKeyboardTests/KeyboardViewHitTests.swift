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
    func keyGridDidDoubleTapShift(_ grid: KeyGridView) { taps.append("shift-lock") }
    func keyGrid(_ grid: KeyGridView, didShiftSlideTo key: Key) {}
    /// Down and up both arrive here; the sweep below counts a landing as one event.
    func keyGrid(_ grid: KeyGridView, globeTouchEvent event: UIEvent?) { taps.append("globe") }
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

    /// There is no dead area anywhere in the key area: every point from the top of the grid
    /// down to the screen edge, gaps and insets included, types exactly one key.
    func testEveryPointOfTheKeyAreaTypesAKey() {
        let bottom = suggestions + keys + bottomInset
        var y = suggestions
        while y < bottom {
            var x: CGFloat = 0
            while x < 390 {
                recorder.taps = []
                tap(at: CGPoint(x: x, y: y))
                // One key per tap (the globe key forwards its raw events, down and up, for one key).
                XCTAssertEqual(Set(recorder.taps).count, 1, "at \(x),\(y): \(recorder.taps)")
                x += 3
            }
            y += 3
        }
    }

    func testSuggestionBarKeepsItsTouches() {
        let hit = view.hitTest(CGPoint(x: 195, y: suggestions / 2), with: nil)
        XCTAssertFalse(hit === view.grid, "a tap on the suggestion strip must not type a key")
    }

    /// A word on the strip is hit anywhere in its cell, not just on the glyphs: the top edge,
    /// the bottom edge and the padding beside the text all select it.
    func testWholeSuggestionCellSelectsTheWord() {
        var picked: [String] = []
        view.suggestionBar.onSelect = { picked.append($0.text) }
        view.suggestionBar.set([Suggestion(text: "a", kind: .alternate),
                                Suggestion(text: "Hallo", kind: .primary),
                                Suggestion(text: "b", kind: .alternate)])
        view.layoutIfNeeded()
        let leading = SuggestionBarView.leadingReserved
        let cellWidth = (390 - leading - SuggestionBarView.trailingReserved(hasLanguage: false)) / 3.0
        for point in [CGPoint(x: leading + cellWidth + 2, y: 1),                    // top-left corner of the middle cell
                      CGPoint(x: leading + cellWidth * 2 - 2, y: suggestions - 1),  // bottom-right corner
                      CGPoint(x: leading + cellWidth * 1.5, y: 3)] {                // above the pill
            let hit = view.hitTest(point, with: nil) as? UIButton
            XCTAssertNotNil(hit, "no button at \(point)")
            hit?.sendActions(for: .touchUpInside)
        }
        XCTAssertEqual(picked, ["Hallo", "Hallo", "Hallo"])
    }

    /// With fewer than three words the ones shown spread over the whole strip, so a single
    /// suggestion is reachable from the "⋯" button right up to the dismiss button.
    func testFewerSuggestionsFillTheStrip() {
        var picked: [String] = []
        view.suggestionBar.onSelect = { picked.append($0.text) }
        view.suggestionBar.set([Suggestion(text: "Hallo", kind: .primary)])
        view.layoutIfNeeded()
        let leading = SuggestionBarView.leadingReserved
        let trailing = SuggestionBarView.trailingReserved(hasLanguage: false)
        for x: CGFloat in [leading + 4, 195, 390 - trailing - 4] {
            let hit = view.hitTest(CGPoint(x: x, y: suggestions / 2), with: nil) as? UIButton
            XCTAssertNotNil(hit, "no button at x=\(x)")
            hit?.sendActions(for: .touchUpInside)
        }
        XCTAssertEqual(picked, ["Hallo", "Hallo", "Hallo"])

        picked = []
        view.suggestionBar.set([Suggestion(text: "links", kind: .alternate), Suggestion(text: "rechts", kind: .primary)])
        view.layoutIfNeeded()
        let half = (390 - leading - trailing) / 2.0
        for x in [leading + half - 4, leading + half + 4] {
            (view.hitTest(CGPoint(x: x, y: suggestions / 2), with: nil) as? UIButton)?.sendActions(for: .touchUpInside)
        }
        XCTAssertEqual(picked, ["links", "rechts"])
    }

    func testEmojiPanelCoversTheStrip() {
        view.emojiDelegate = nil
        view.isEmojiVisible = true
        let hit = view.hitTest(CGPoint(x: 195, y: suggestions + keys + 10), with: nil)
        XCTAssertFalse(hit === view.grid)
        XCTAssertTrue(hit?.isDescendant(of: view.emojiPanel!) ?? false)
    }

    /// The "⋯" button sits at the leading edge of the strip and opens the action menu; while
    /// the menu is open every touch belongs to it, and a tap beside the card closes it.
    func testActionMenuOwnsTouchesWhileOpen() {
        var opened = 0
        view.suggestionBar.onActions = { opened += 1 }
        let button = view.hitTest(CGPoint(x: 20, y: suggestions / 2), with: nil) as? UIButton
        XCTAssertTrue(button === view.suggestionBar.actionsButton, "no actions button at the leading edge")
        button?.sendActions(for: .touchUpInside)
        XCTAssertEqual(opened, 1)

        view.isActionMenuVisible = true
        let menu = view.actionMenu!
        menu.set(actions: [KeyboardAction(kind: .clipboard, title: "Zwischenablage", symbol: "doc.on.clipboard"),
                           KeyboardAction(kind: .dismiss, title: "Tastatur ausblenden", symbol: "keyboard.chevron.compact.down")])
        var picked: [KeyboardAction.Kind] = []
        var closed = 0
        menu.onSelect = { picked.append($0.kind) }
        menu.onClose = { closed += 1 }
        view.layoutIfNeeded()
        let onGrid = view.hitTest(CGPoint(x: 300, y: suggestions + keys - 10), with: nil)
        XCTAssertFalse(onGrid === view.grid, "the grid must not type while the menu is open")
        XCTAssertTrue(onGrid?.isDescendant(of: menu) ?? false)
        let row = view.hitTest(CGPoint(x: 60, y: suggestions + ActionMenuView.rowHeight / 2), with: nil) as? UIButton
        XCTAssertNotNil(row, "no menu row under the button")
        row?.sendActions(for: .touchUpInside)
        XCTAssertEqual(picked, [.clipboard])

        view.isActionMenuVisible = false
        let hit = view.hitTest(CGPoint(x: 300, y: suggestions + keys - 10), with: nil)
        XCTAssertTrue(hit === view.grid, "the grid types again once the menu is closed")
    }

    func testClipboardPanelCoversTheKeys() {
        view.clipboardDelegate = nil
        view.isClipboardVisible = true
        XCTAssertTrue(view.grid.isHidden)
        XCTAssertTrue(view.suggestionBar.isHidden)
        let hit = view.hitTest(CGPoint(x: 195, y: suggestions + keys + 10), with: nil)
        XCTAssertFalse(hit === view.grid)
        XCTAssertTrue(hit?.isDescendant(of: view.clipboardPanel!) ?? false)
        view.isEmojiVisible = true
        XCTAssertFalse(view.isClipboardVisible, "one panel at a time")
        XCTAssertTrue(view.clipboardPanel!.isHidden)
    }
}
