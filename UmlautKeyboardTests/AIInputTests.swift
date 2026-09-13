import XCTest
import KeyboardCore
@testable import Umlaut

/// The AI entries of the strip and the edits the panel makes, against the in-memory document.
final class AIInputTests: XCTestCase {
    static let lexicon: Lexicon = try! Lexicon.loadBundled()
    var engine: KeyboardEngine!
    var proxy: FakeTextProxy!
    var input: InputController!
    var settings: KeyboardSettings!
    let keyMap = KeyMap.reference()

    override func setUp() {
        super.setUp()
        settings = KeyboardSettings(defaults: UserDefaults(suiteName: "ai-input-\(UUID())")!)
        settings.aiEnabled = true
        proxy = FakeTextProxy()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ai-input-\(UUID()).json")
        engine = KeyboardEngine(lexicon: Self.lexicon, user: UserLexicon(fileURL: url))
        input = InputController(engine: engine, settings: settings, proxy: proxy)
        input.keyMap = keyMap
        input.traits = FieldTraits()
        input.refresh()
    }

    private func key(_ c: Character) -> Key { GermanLayouts.letters().allKeys.first { $0.character == c && $0.isLetter }! }

    private func type(_ s: String) {
        for c in s {
            switch c {
            case " ": input.handle(key: GermanLayouts.space)
            case ".": input.handle(key: GermanLayouts.period)
            default: input.handle(key: key(Character(c.lowercased())))
            }
        }
    }

    // MARK: Sentence check

    func testFinishedSentenceIsReportedOnce() {
        var reported: [String] = []
        input.onSentenceCompleted = { reported.append($0) }
        type("das ist ein test. ")
        XCTAssertEqual(reported, ["Das ist ein Test."])
        type("und ")
        XCTAssertEqual(reported.count, 1, "a word after the sentence is no new sentence")
    }

    func testCorrectedSentenceFillsTheStripAndReplacesOnTap() {
        type("das ist ein test. ")
        input.aiSentence = ("Das ist ein Test.", "Das ist ein Test!")
        XCTAssertEqual(input.state.suggestions, [Suggestion(text: "Das ist ein Test!", kind: .ai)])
        input.accept(input.state.suggestions[0])
        XCTAssertEqual(proxy.text, "Das ist ein Test! ")
        XCTAssertNil(input.aiSentence)
        XCTAssertFalse(input.state.suggestions.contains { $0.kind == .ai })
    }

    func testCorrectionDisappearsWhenTheSentenceChanges() {
        type("das ist ein test. ")
        input.aiSentence = ("Das ist ein Test.", "Das ist ein Test!")
        XCTAssertTrue(input.state.suggestions.contains { $0.kind == .ai })
        type("mehr ")
        XCTAssertFalse(input.state.suggestions.contains { $0.kind == .ai }, "the sentence no longer ends the text")
    }

    func testStaleCorrectionIsNotApplied() {
        type("das ist ein test. ")
        input.aiSentence = ("Das ist ein Test.", "Das ist ein Test!")
        input.handle(key: GermanLayouts.backspace)
        XCTAssertTrue(input.state.suggestions.contains { $0.kind == .ai }, "the sentence still ends the text without the space")
        input.handle(key: GermanLayouts.backspace)   // the period goes: no finished sentence any more
        XCTAssertFalse(input.state.suggestions.contains { $0.kind == .ai })
        input.applyAISentence()
        XCTAssertEqual(proxy.text, "Das ist ein Test", "nothing replaced")
        XCTAssertNil(input.aiSentence)
    }

    // MARK: Continuations

    func testContinuationsShareTheStripWhileTheContextHolds() {
        var boundaries: [String] = []
        input.onWordBoundary = { boundaries.append($0) }
        type("hallo ")
        XCTAssertEqual(boundaries.last, "Hallo ")
        input.aiContinuations = ("Hallo ", ["wie geht es dir", "zusammen"])
        let ai = input.state.suggestions.filter { $0.kind == .ai }.map(\.text)
        XCTAssertEqual(ai, ["wie geht es dir", "zusammen"])
        XCTAssertEqual(input.state.suggestions.count, 3, "one engine prediction fills the third cell")
        input.accept(Suggestion(text: "wie geht es dir", kind: .ai))
        XCTAssertEqual(proxy.text, "Hallo wie geht es dir ")
        type("w")
        XCTAssertFalse(input.state.suggestions.contains { $0.kind == .ai })
    }

    // MARK: Panel edits

    func testReplaceTextBeforeCursorOnlyWhenItStillMatches() {
        type("hallo welt")
        XCTAssertTrue(input.replaceTextBeforeCursor("Hallo welt", with: "Hallo Welt!"))
        XCTAssertEqual(proxy.text, "Hallo Welt!")
        XCTAssertFalse(input.replaceTextBeforeCursor("gone", with: "x"))
        XCTAssertEqual(proxy.text, "Hallo Welt!")
        // Undo is the same operation the other way round.
        XCTAssertTrue(input.replaceTextBeforeCursor("Hallo Welt!", with: "Hallo welt"))
        XCTAssertEqual(proxy.text, "Hallo welt")
    }

    func testInsertAITextJoinsWithASpaceAndReturnsWhatWasInserted() {
        type("hallo")
        let inserted = input.insertAIText("liebe Grüße")
        XCTAssertEqual(inserted, " liebe Grüße ")
        XCTAssertEqual(proxy.text, "Hallo liebe Grüße ")
        input.handle(key: GermanLayouts.period)
        XCTAssertEqual(proxy.text, "Hallo liebe Grüße. ", "punctuation swallows the auto space")
    }

    func testTextBeforeCursorReadsTheHost() {
        proxy.text = "Schon da"
        proxy.cursor = 8
        input.textDidChangeExternally()   // the host reports the change, as it does for a real field
        XCTAssertEqual(input.textBeforeCursor, "Schon da")
        XCTAssertNil(input.selectedText)
    }

    func testNoAIEntriesInSensitiveFields() {
        var traits = FieldTraits()
        traits.isSecure = true
        input.traits = traits
        var reported = 0
        input.onSentenceCompleted = { _ in reported += 1 }
        type("das ist ein test. ")
        XCTAssertEqual(reported, 0)
        input.aiSentence = ("Das ist ein Test.", "Das ist ein Test!")
        XCTAssertTrue(input.state.suggestions.isEmpty)
    }
}
