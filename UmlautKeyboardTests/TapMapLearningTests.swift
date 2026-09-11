import XCTest
import KeyboardCore
@testable import Umlaut

/// The tap map learns from `InputController`: every letter tap is remembered with its touch point
/// and fed into the map once the word is committed – confirmed as typed, or re-attributed by an
/// autocorrection – and taken back again when the user reverts that correction.
final class TapMapLearningTests: XCTestCase {
    static let lexicon: Lexicon = try! Lexicon.loadBundled()

    var proxy: FakeTextProxy!
    var input: InputController!
    var settings: KeyboardSettings!
    var tapMap: TapMap!
    let keyMap = KeyMap.reference()

    override func setUp() {
        super.setUp()
        settings = KeyboardSettings(defaults: UserDefaults(suiteName: "tapmap-tests-\(UUID())")!)
        proxy = FakeTextProxy()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tapmap-tests-\(UUID()).json")
        let engine = KeyboardEngine(lexicon: Self.lexicon, user: UserLexicon(fileURL: url))
        tapMap = TapMap(fileURL: nil)
        input = InputController(engine: engine, settings: settings, proxy: proxy, tapMap: tapMap)
        input.keyMap = keyMap
        input.traits = FieldTraits()
        input.refresh()
    }

    private func key(_ c: Character) -> Key {
        GermanLayouts.letters().allKeys.first { $0.character == c && $0.isLetter }!
    }

    private func center(_ c: Character) -> CGPoint { keyMap.centers[Int(KeyAlphabet.code(for: c)!)] }

    /// Taps every letter `dx`/`dy` pitches off its centre; space and period are plain key events.
    private func type(_ s: String, dx: CGFloat = 0, dy: CGFloat = 0) {
        for c in s {
            switch c {
            case " ": input.handle(key: GermanLayouts.space)
            case ".": input.handle(key: GermanLayouts.period)
            default:
                let p = center(c)
                input.handle(key: key(c), touch: CGPoint(x: p.x + dx * keyMap.pitchX, y: p.y + dy * keyMap.pitchY))
            }
        }
    }

    private func learnedDx(_ c: Character) -> Float {
        tapMap.layer(for: keyMap)!.stats[Int(KeyAlphabet.code(for: c)!)].dx
    }

    // MARK: Tests

    func testCommittedWordTeachesEveryTap() {
        type("hallo ")
        XCTAssertEqual(proxy.text, "Hallo ")
        XCTAssertEqual(tapMap.totalSamples, 5)
        // A second word keeps its own taps apart from the first.
        type("welt", dx: 0.2)
        XCTAssertEqual(tapMap.totalSamples, 5)
        type(".")
        XCTAssertEqual(tapMap.totalSamples, 9)
        XCTAssertEqual(learnedDx("w"), 0.2, accuracy: 1e-3)
        XCTAssertEqual(learnedDx("h"), 0, accuracy: 1e-3)
    }

    func testOffsetsReachTheGridStateAndFollowTheSetting() {
        XCTAssertEqual(input.state.tapOffsets, .neutral)
        type("hallo ")
        XCTAssertNotEqual(input.state.tapOffsets, .neutral)
        settings.adaptiveTapMap = false
        input.refresh()
        XCTAssertNil(input.state.tapOffsets)
        // Off: nothing is learned either.
        type("welt ")
        XCTAssertEqual(tapMap.totalSamples, 5)
        // Other layers never carry offsets.
        settings.adaptiveTapMap = true
        input.handle(key: GermanLayouts.toSymbols)
        XCTAssertNil(input.state.tapOffsets)
        input.handle(key: GermanLayouts.toLetters)
        XCTAssertNotNil(input.state.tapOffsets)
    }

    func testAutocorrectionReattributesTapsAndBackspaceTakesItBack() {
        // "hakko" → "Hallo": the k taps near the k/l boundary are learned as taps on l.
        let kEdge = CGPoint(x: center("k").x + 0.45 * keyMap.pitchX, y: center("k").y)
        for c in "ha" { input.handle(key: key(c), touch: center(c)) }
        input.handle(key: key("k"), touch: kEdge)
        input.handle(key: key("k"), touch: kEdge)
        input.handle(key: key("o"), touch: center("o"))
        input.handle(key: GermanLayouts.space)
        XCTAssertEqual(proxy.text, "Hallo ")
        XCTAssertEqual(tapMap.totalSamples, 5)
        let layer = tapMap.layer(for: keyMap)!
        XCTAssertEqual(layer.stats[Int(KeyAlphabet.code(for: "l")!)].count, 2)
        XCTAssertLessThan(learnedDx("l"), -0.4)
        XCTAssertEqual(layer.stats[Int(KeyAlphabet.code(for: "k")!)].count, 0)

        // The user did mean "Hakko": what the correction taught is undone.
        input.handle(key: GermanLayouts.backspace)
        XCTAssertEqual(proxy.text, "Hakko")
        XCTAssertEqual(tapMap.totalSamples, 0)
        XCTAssertNil(tapMap.layer(for: keyMap)?.stats.first { $0.count > 0 })
    }

    func testBackspaceDropsTheDeletedTapAndKeepsTheRestAligned() {
        type("hal", dx: 0.1)
        input.handle(key: GermanLayouts.backspace)
        type("llo ", dx: -0.1)
        XCTAssertEqual(proxy.text, "Hallo ")
        XCTAssertEqual(tapMap.totalSamples, 5)
        XCTAssertEqual(learnedDx("h"), 0.1, accuracy: 1e-3)
        XCTAssertEqual(learnedDx("o"), -0.1, accuracy: 1e-3)
    }

    func testTapsWithoutPointsAndCursorMovesTeachNothing() {
        // Plain key events (no touch) are the old API: nothing to learn from.
        for c in "hallo" { input.handle(key: key(c)) }
        input.handle(key: GermanLayouts.space)
        XCTAssertEqual(tapMap.totalSamples, 0)
        // A word the cursor was moved into is not trusted, even when the tap count fits.
        type("wel")
        input.moveCursor(by: -1)
        input.moveCursor(by: 1)
        type("t ")
        XCTAssertEqual(tapMap.totalSamples, 0)
        // Shift-slide capitals keep the rest of the word learnable.
        input.shiftSlide(to: key("h"))
        type("allo ")
        XCTAssertEqual(tapMap.totalSamples, 4)
    }

    func testSecureAndJustinFieldsDoNotLearn() {
        var traits = FieldTraits()
        traits.isSecure = true
        input.traits = traits
        type("hallo ")
        XCTAssertEqual(tapMap.totalSamples, 0)
        // …but the learned offsets still help hitting keys there.
        XCTAssertNotNil(input.state.tapOffsets)

        input.traits = FieldTraits()
        settings.justinMode = true
        type("hallo ")
        XCTAssertEqual(tapMap.totalSamples, 0)
    }
}

/// `KeyGridView` reports the landing point of a plain tap so the coordinator can pass it on.
@MainActor
final class KeyGridTapPointTests: XCTestCase {
    private final class PointRecorder: KeyGridDelegate {
        var taps: [(id: String, point: CGPoint?)] = []
        var keyPreviewEnabled = false
        var swipeTypingEnabled = true
        var swipeTrailEnabled = false
        var longPressNumbersEnabled = true

        func keyGrid(_ grid: KeyGridView, didTap key: Key) { taps.append((key.id, nil)) }
        func keyGrid(_ grid: KeyGridView, didTap key: Key, at point: CGPoint) { taps.append((key.id, point)) }
        func keyGrid(_ grid: KeyGridView, didInsertAlternate text: String, for key: Key) {}
        func keyGrid(_ grid: KeyGridView, didSwipe path: [CGPoint], keyMap: KeyMap) {}
        func keyGrid(_ grid: KeyGridView, didLongPress key: Key) {}
        func keyGridBackspaceRepeat(_ grid: KeyGridView, wordwise: Bool) {}
        func keyGrid(_ grid: KeyGridView, moveCursorBy offset: Int) {}
        func keyGridDidDoubleTapShift(_ grid: KeyGridView) {}
        func keyGrid(_ grid: KeyGridView, didShiftSlideTo key: Key) {}
        func keyGrid(_ grid: KeyGridView, globeTouchEvent event: UIEvent?) {}
    }

    private final class PointTouch: UITouch {
        var point: CGPoint = .zero
        override func location(in view: UIView?) -> CGPoint { point }
    }

    func testTapReportsLandingPointAndUsesTheOffsets() {
        let settings = KeyboardSettings(defaults: UserDefaults(suiteName: "grid-point-tests-\(UUID())")!)
        let theme = KeyboardTheme.current(traits: UITraitCollection(userInterfaceStyle: .light), settings: settings)
        let grid = KeyGridView(theme: theme, feedback: Feedback(settings: settings))
        let recorder = PointRecorder()
        grid.delegate = recorder
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        grid.frame = CGRect(x: 0, y: 44, width: 390, height: 216)
        window.addSubview(grid)
        window.isHidden = false
        grid.configure(layout: GermanLayouts.letters(), metrics: .phonePortrait)
        grid.layoutIfNeeded()

        let geometry = grid.geometry!
        let k = geometry.keyFrames.first { $0.key.id == "k" }!, l = geometry.keyFrames.first { $0.key.id == "l" }!
        let edge = CGPoint(x: l.frame.minX + 2, y: k.center.y)

        func tap(_ p: CGPoint) {
            let t = PointTouch(); t.point = p
            grid.touchesBegan([t], with: nil)
            grid.touchesEnded([t], with: nil)
        }

        tap(edge)
        XCTAssertEqual(recorder.taps.last?.id, "l")
        XCTAssertEqual(recorder.taps.last?.point, edge)

        // A map that says this user taps everything a fifth of a key to the right turns the same
        // touch into a k.
        var dx = [CGFloat](repeating: 0.2, count: KeyAlphabet.count)
        dx[Int(KeyAlphabet.code(for: "ä")!)] = 0
        grid.tapOffsets = TapMap.Offsets(dx: dx, dy: [CGFloat](repeating: 0, count: KeyAlphabet.count))
        tap(edge)
        XCTAssertEqual(recorder.taps.last?.id, "k")
        XCTAssertEqual(recorder.taps.last?.point, edge)
    }
}
