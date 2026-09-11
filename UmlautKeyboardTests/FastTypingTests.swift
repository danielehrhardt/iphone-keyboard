import XCTest
import KeyboardCore
@testable import Umlaut

/// A document that counts how often the keyboard reads it. In the extension every read is a
/// round trip to the host app, so a key event must get by on a couple of them.
private final class CountingProxy: TextProxy {
    let inner = FakeTextProxy()
    var reads = 0
    var textBefore: String { reads += 1; return inner.textBefore }
    var textAfter: String { reads += 1; return inner.textAfter }
    func insert(_ text: String) { inner.insert(text) }
    func deleteBackward() { inner.deleteBackward() }
    func moveCursor(by offset: Int) { inner.moveCursor(by: offset) }
}

private final class StateRecorder: InputControllerDelegate {
    var updates = 0
    func inputController(_ c: InputController, didUpdate state: InputUIState) { updates += 1 }
    func inputControllerRequestsGlobe(_ c: InputController) {}
    func inputControllerRequestsEmoji(_ c: InputController) {}
    func inputControllerRequestsDismiss(_ c: InputController) {}
}

/// What a key event may cost: the main thread must be free for the next touch right away.
final class FastTypingTests: XCTestCase {
    private var proxy: CountingProxy!
    private var input: InputController!
    private var recorder: StateRecorder!

    override func setUp() {
        super.setUp()
        let settings = KeyboardSettings(defaults: UserDefaults(suiteName: "fast-tests-\(UUID())")!)
        proxy = CountingProxy()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fast-tests-\(UUID()).json")
        let engine = KeyboardEngine(lexicon: InputControllerTests.lexicon, user: UserLexicon(fileURL: url))
        input = InputController(engine: engine, settings: settings, proxy: proxy)
        input.keyMap = KeyMap.reference()
        input.traits = FieldTraits()
        recorder = StateRecorder()
        input.delegate = recorder
        input.refresh()
    }

    private func key(_ c: Character) -> Key {
        GermanLayouts.letters().allKeys.first { $0.character == c && $0.isLetter }!
    }

    func testLetterTapReadsTheDocumentTwiceAtMost() {
        for c in "wahrscheinlich" {
            proxy.reads = 0
            input.handle(key: key(c))
            XCTAssertLessThanOrEqual(proxy.reads, 2, "typing \(c): before and after the edit, nothing else")
        }
        XCTAssertEqual(proxy.inner.text, "Wahrscheinlich")
    }

    func testSpaceWithAutocorrectReadsTheDocumentAFewTimes() {
        for c in "hakko" { input.handle(key: key(c)) }
        proxy.reads = 0
        input.handle(key: GermanLayouts.space)
        XCTAssertEqual(proxy.inner.text, "Hallo ")
        // Once on entry, once after the correction, once after the space.
        XCTAssertLessThanOrEqual(proxy.reads, 3, "\(proxy.reads) reads")
    }

    func testHostEchoOfOurOwnEditCostsOneReadAndNoUpdate() {
        input.handle(key: key("h"))
        let updates = recorder.updates
        proxy.reads = 0
        // The host reports every edit back through `textDidChange`; ours must be recognised.
        input.textDidChangeExternally()
        XCTAssertEqual(proxy.reads, 1)
        XCTAssertEqual(recorder.updates, updates)
        // A real external change still refreshes.
        proxy.inner.insert("allo ")
        input.textDidChangeExternally()
        XCTAssertGreaterThan(recorder.updates, updates)
        XCTAssertEqual(input.state.shift, .off)
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
