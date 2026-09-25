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

    /// A thumb aiming at the top row at speed lands a little high as often as low: a tap in the
    /// strip's bottom margin, below the words, types the key underneath instead of picking a word.
    func testTapJustAboveTheTopRowTypesTheKey() {
        view.suggestionBar.set([Suggestion(text: "a", kind: .alternate),
                                Suggestion(text: "Hallo", kind: .primary),
                                Suggestion(text: "b", kind: .alternate)])
        view.layoutIfNeeded()
        let t = view.grid.geometry!.keyFrames.first { $0.key.id == "t" }!
        tap(at: CGPoint(x: t.center.x, y: suggestions - KeyboardView.gridReachIntoStrip + 1))
        XCTAssertEqual(recorder.taps, ["t"])
        let above = view.hitTest(CGPoint(x: t.center.x, y: suggestions - KeyboardView.gridReachIntoStrip - 1), with: nil)
        XCTAssertFalse(above === view.grid, "the words keep the rest of the strip")
    }

    /// A word on the strip is hit anywhere in its cell, not just on the glyphs: the top edge,
    /// the bottom edge (down to the keys' reach) and the padding beside the text all select it.
    func testWholeSuggestionCellSelectsTheWord() {
        var picked: [String] = []
        view.suggestionBar.onSelect = { picked.append($0.text) }
        view.suggestionBar.set([Suggestion(text: "a", kind: .alternate),
                                Suggestion(text: "Hallo", kind: .primary),
                                Suggestion(text: "b", kind: .alternate)])
        view.layoutIfNeeded()
        let words = view.suggestionBar.wordArea
        let leading = words.minX
        let cellWidth = words.width / 3.0
        let bottom = suggestions - KeyboardView.gridReachIntoStrip - 1
        for point in [CGPoint(x: leading + cellWidth + 2, y: 1),                    // top-left corner of the middle cell
                      CGPoint(x: leading + cellWidth * 2 - 2, y: bottom),           // bottom-right corner
                      CGPoint(x: leading + cellWidth * 1.5, y: 3)] {                // above the pill
            let hit = view.hitTest(point, with: nil) as? UIButton
            XCTAssertNotNil(hit, "no button at \(point)")
            hit?.sendActions(for: .touchUpInside)
        }
        XCTAssertEqual(picked, ["Hallo", "Hallo", "Hallo"])
    }

    /// With fewer than three words the ones shown spread over the whole strip, so a single
    /// suggestion is reachable from the leading icons right up to the dismiss button.
    func testFewerSuggestionsFillTheStrip() {
        var picked: [String] = []
        view.suggestionBar.onSelect = { picked.append($0.text) }
        view.suggestionBar.set([Suggestion(text: "Hallo", kind: .primary)])
        view.layoutIfNeeded()
        let leading = view.suggestionBar.wordArea.minX
        let trailing = 390 - view.suggestionBar.wordArea.maxX
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

    /// Every action in the strip exists once and is one tap away: the clipboard sits at the
    /// leading edge (no "⋯" dropdown repeating the language and hide buttons), the language
    /// badge and the hide button at the trailing edge.
    func testStripIconsActDirectly() {
        var calls: [String] = []
        view.suggestionBar.onClipboard = { calls.append("clipboard") }
        view.suggestionBar.onLanguage = { calls.append("language") }
        view.suggestionBar.onDismiss = { calls.append("dismiss") }
        view.suggestionBar.language = .german
        view.suggestionBar.showsClipboard = true
        view.layoutIfNeeded()
        for x: CGFloat in [20, 390 - 60, 390 - 20] {
            let hit = view.hitTest(CGPoint(x: x, y: suggestions / 2), with: nil) as? UIControl
            XCTAssertNotNil(hit, "no control at x=\(x)")
            hit?.sendActions(for: .touchUpInside)
        }
        XCTAssertEqual(calls, ["clipboard", "language", "dismiss"])

        view.suggestionBar.showsClipboard = false
        view.suggestionBar.language = nil
        view.layoutIfNeeded()
        XCTAssertEqual(view.suggestionBar.wordArea.minX, SuggestionBarView.edgeInset, "no clipboard: the words start at the edge")
        let hit = view.hitTest(CGPoint(x: 390 - 60, y: suggestions / 2), with: nil)
        XCTAssertFalse(hit === view.suggestionBar.languageButton, "a hidden badge takes no touches")
    }

    /// While a glide is in flight the strip shows the word being traced instead of the
    /// suggestions, and a tap on it picks nothing.
    func testGlidePreviewReplacesTheWords() {
        var picked: [String] = []
        view.suggestionBar.onSelect = { picked.append($0.text) }
        view.suggestionBar.set([Suggestion(text: "Hallo", kind: .primary)])
        view.suggestionBar.glidePreview = "Wochenende"
        view.layoutIfNeeded()
        (view.hitTest(CGPoint(x: 195, y: suggestions / 2), with: nil) as? UIButton)?.sendActions(for: .touchUpInside)
        XCTAssertTrue(picked.isEmpty)
        view.suggestionBar.glidePreview = nil
        (view.hitTest(CGPoint(x: 195, y: suggestions / 2), with: nil) as? UIButton)?.sendActions(for: .touchUpInside)
        XCTAssertEqual(picked, ["Hallo"])
    }

    /// A history with nothing in it says so, and offers nothing to delete.
    func testEmptyClipboardSaysSo() {
        view.clipboardDelegate = nil
        view.isClipboardVisible = true
        view.clipboardPanel!.set(items: [])
        view.layoutIfNeeded()
        func all(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(all) }
        let views = all(view.clipboardPanel!)
        let message = views.compactMap { $0 as? UILabel }.first { $0.text?.hasPrefix("Noch nichts kopiert") == true }
        XCTAssertNotNil(message)
        XCTAssertEqual(message?.isHidden, false)
        let clear = views.first { $0.accessibilityIdentifier == "clipboard-clear" }
        XCTAssertEqual(clear?.isHidden, true)
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
