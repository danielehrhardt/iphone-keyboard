import XCTest
import KeyboardCore
@testable import Umlaut

/// A document that counts how often the keyboard reads it. In the extension every read is a
/// round trip to the host app, so a key event must get by without one.
private final class CountingProxy: TextProxy {
    let inner = FakeTextProxy()
    var reads = 0
    var textBefore: String { reads += 1; return inner.textBefore }
    var textAfter: String { reads += 1; return inner.textAfter }
    func insert(_ text: String) { inner.insert(text) }
    func deleteBackward() { inner.deleteBackward() }
    func moveCursor(by offset: Int) { inner.moveCursor(by: offset) }
}

/// A host that is slow: edits queue up and only show in the document once it catches up, the
/// way a busy app answers the keyboard's reads with text from several keystrokes ago.
private final class LaggingProxy: TextProxy {
    let inner = FakeTextProxy()
    private var pending: [() -> Void] = []
    var textBefore: String { inner.textBefore }
    var textAfter: String { inner.textAfter }
    func insert(_ text: String) { pending.append { self.inner.insert(text) } }
    func deleteBackward() { pending.append { self.inner.deleteBackward() } }
    func moveCursor(by offset: Int) { pending.append { self.inner.moveCursor(by: offset) } }

    func catchUp(_ edits: Int = .max) {
        let n = min(edits, pending.count)
        for edit in pending.prefix(n) { edit() }
        pending.removeFirst(n)
    }
}

private final class StateRecorder: InputControllerDelegate {
    var updates = 0
    func inputController(_ c: InputController, didUpdate state: InputUIState) { updates += 1 }
    func inputControllerRequestsGlobe(_ c: InputController) {}
    func inputControllerRequestsEmoji(_ c: InputController) {}
    func inputControllerRequestsDismiss(_ c: InputController) {}
}

/// What a key event may cost: the main thread must be free for the next touch right away, and
/// no keystroke may wait for – or be misread because of – a slow host.
final class FastTypingTests: XCTestCase {
    private var proxy: CountingProxy!
    private var input: InputController!
    private var recorder: StateRecorder!

    override func setUp() {
        super.setUp()
        proxy = CountingProxy()
        recorder = StateRecorder()
        input = makeInput(proxy: proxy)
        input.delegate = recorder
        input.refresh()
        proxy.reads = 0
    }

    private func makeInput(proxy: TextProxy) -> InputController {
        let settings = KeyboardSettings(defaults: UserDefaults(suiteName: "fast-tests-\(UUID())")!)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fast-tests-\(UUID()).json")
        let engine = KeyboardEngine(lexicon: InputControllerTests.lexicon, user: UserLexicon(fileURL: url))
        let input = InputController(engine: engine, settings: settings, proxy: proxy)
        input.keyMap = KeyMap.reference()
        input.traits = FieldTraits()
        return input
    }

    private func key(_ c: Character) -> Key {
        GermanLayouts.letters().allKeys.first { $0.character == c && $0.isLetter }!
    }

    func testLetterTapNeverReadsTheDocument() {
        for c in "wahrscheinlich" {
            input.handle(key: key(c))
            XCTAssertEqual(proxy.reads, 0, "typing \(c)")
        }
        XCTAssertEqual(proxy.inner.text, "Wahrscheinlich")
        XCTAssertEqual(input.composingWord, "Wahrscheinlich")
    }

    func testSpaceWithAutocorrectNeverReadsTheDocument() {
        for c in "hakko" { input.handle(key: key(c)) }
        input.handle(key: GermanLayouts.space)
        XCTAssertEqual(proxy.inner.text, "Hallo ")
        XCTAssertEqual(proxy.reads, 0)
        input.handle(key: GermanLayouts.backspace)
        XCTAssertEqual(proxy.inner.text, "Hakko")
        XCTAssertEqual(proxy.reads, 0)
    }

    func testCursorMovesNeverReadTheDocument() {
        for c in "hallo" { input.handle(key: key(c)) }
        input.moveCursor(by: -2)
        XCTAssertEqual(proxy.reads, 0)
        XCTAssertEqual(input.composingWord, "", "caret inside the word")
        XCTAssertNil(input.state.letterPrior)
        input.moveCursor(by: 5)
        XCTAssertEqual(proxy.reads, 0)
        XCTAssertEqual(input.composingWord, "Hallo", "clamped at the end of the text")
        XCTAssertEqual(proxy.inner.cursor, 5)
    }

    func testHostEchoOfOurOwnEditCostsOneSnapshotAndNoUpdate() {
        input.handle(key: key("h"))
        let updates = recorder.updates
        proxy.reads = 0
        // The host reports every edit back through `textDidChange`; ours must be recognised.
        input.textDidChangeExternally()
        XCTAssertEqual(proxy.reads, 2, "before and after the caret, once")
        XCTAssertEqual(recorder.updates, updates)
        // A real external change still refreshes.
        proxy.inner.insert("allo ")
        input.textDidChangeExternally()
        XCTAssertGreaterThan(recorder.updates, updates)
        XCTAssertEqual(input.state.shift, .off)
        XCTAssertEqual(input.composingWord, "")
    }

    func testShiftIsRightWhileTheHostLags() {
        let host = LaggingProxy()
        let input = makeInput(proxy: host)
        input.refresh()
        // Sentence start: the first letter is capitalised, the second must not be – even though
        // the host has not shown the first one yet.
        input.handle(key: key("h"))
        input.handle(key: key("a"))
        input.handle(key: key("l"))
        host.catchUp()
        XCTAssertEqual(host.inner.text, "Hal")
    }

    func testLaggingHostEchoesNeverOverrideOurOwnEdits() {
        let host = LaggingProxy()
        let input = makeInput(proxy: host)
        input.refresh()
        for c in "hakko" { input.handle(key: key(c)) }
        // The host has processed two keystrokes and reports them: that is old news, not a change.
        host.catchUp(2)
        input.textDidChangeExternally()
        XCTAssertEqual(host.inner.text, "Ha")
        XCTAssertEqual(input.composingWord, "Hakko")
        XCTAssertEqual(input.state.suggestions.first { $0.kind == .primary }?.text, "Hallo")
        // Space arrives before the host caught up: the whole word is corrected, not the part
        // the host had shown.
        input.handle(key: GermanLayouts.space)
        host.catchUp()
        XCTAssertEqual(host.inner.text, "Hallo ")
        input.textDidChangeExternally()
        XCTAssertEqual(input.composingWord, "")
        XCTAssertEqual(input.state.suggestions.first?.kind, .prediction)
    }

    func testExternalChangeOnALaggingHostIsStillSeen() {
        let host = LaggingProxy()
        let input = makeInput(proxy: host)
        input.refresh()
        for c in "hallo" { input.handle(key: key(c)) }
        host.catchUp()
        // The user taps into the word: not a state we produced, so it replaces our view.
        host.inner.cursor = 2
        input.textDidChangeExternally()
        XCTAssertEqual(input.composingWord, "")
        input.handle(key: key("x"))
        host.catchUp()
        XCTAssertEqual(host.inner.text, "Haxllo")
    }

    func testSuggestionsArriveOffTheMainThreadWhileShiftIsImmediate() {
        input.suggestionQueue = DispatchQueue(label: "fast-tests-suggestions")
        for c in "wochene" { input.handle(key: key(c)) }
        // The key event returned: the document and the shift state are already right.
        XCTAssertEqual(proxy.inner.text, "Wochene")
        XCTAssertEqual(input.state.shift, .off)
        let done = expectation(description: "strip")
        func poll() {
            if input.state.suggestions.contains(where: { $0.text == "Wochenende" }) { done.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: poll)
        }
        poll()
        wait(for: [done], timeout: 5)
    }

    func testStaleSuggestionsAreDropped() {
        input.suggestionQueue = DispatchQueue(label: "fast-tests-suggestions")
        for c in "wochene" { input.handle(key: key(c)) }
        // The strip for "wochene" is still in flight when the layer switches: it must not land.
        input.handle(key: Key(action: .switchLayer(.symbols), label: "123"))
        let done = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(input.state.layer, .symbols)
        XCTAssertTrue(input.state.suggestions.isEmpty, "\(input.state.suggestions)")
    }
}
