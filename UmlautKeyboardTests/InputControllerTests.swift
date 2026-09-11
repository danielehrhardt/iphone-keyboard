import XCTest
import KeyboardCore
@testable import Umlaut

/// In-memory document with a cursor, mimicking `UITextDocumentProxy` semantics.
final class FakeTextProxy: TextProxy {
    var text: String = ""
    var cursor: Int = 0

    var textBefore: String { String(text.prefix(cursor)) }
    var textAfter: String { String(text.dropFirst(cursor)) }

    func insert(_ s: String) {
        let idx = text.index(text.startIndex, offsetBy: cursor)
        text.insert(contentsOf: s, at: idx)
        cursor += s.count
    }

    func deleteBackward() {
        guard cursor > 0 else { return }
        let idx = text.index(text.startIndex, offsetBy: cursor - 1)
        text.remove(at: idx)
        cursor -= 1
    }

    func moveCursor(by offset: Int) { cursor = max(0, min(text.count, cursor + offset)) }
}

final class InputControllerTests: XCTestCase {
    static let lexicon: Lexicon = try! Lexicon.loadBundled()
    /// Fresh personal dictionary per test so learned/rejected words don't leak between tests.
    var engine: KeyboardEngine!

    var proxy: FakeTextProxy!
    var input: InputController!
    var settings: KeyboardSettings!
    let keyMap = KeyMap.reference()

    override func setUp() {
        super.setUp()
        let suite = UserDefaults(suiteName: "ic-tests-\(UUID())")!
        settings = KeyboardSettings(defaults: suite)
        proxy = FakeTextProxy()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ic-tests-\(UUID()).json")
        engine = KeyboardEngine(lexicon: Self.lexicon, user: UserLexicon(fileURL: url))
        input = InputController(engine: engine, settings: settings, proxy: proxy)
        input.keyMap = keyMap
        input.traits = FieldTraits()
        input.refresh()
    }

    func key(_ c: Character) -> Key {
        GermanLayouts.letters().allKeys.first { $0.character == c && $0.isLetter }!
    }

    func type(_ s: String) {
        for c in s {
            switch c {
            case " ": input.handle(key: GermanLayouts.space)
            case ".": input.handle(key: GermanLayouts.period)
            default:
                // Type lowercase; shift state decides the case like a real tap.
                input.handle(key: key(Character(c.lowercased())))
            }
        }
    }

    func swipe(_ word: String) {
        let codes = KeyAlphabet.swipeCodes(word)
        var pts: [CGPoint] = []
        let centers = codes.map { keyMap.centers[Int($0)] }
        for i in 1..<centers.count {
            let a = centers[i - 1], b = centers[i]
            for s in 0..<8 { let t = CGFloat(s) / 8; pts.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)) }
        }
        pts.append(centers.last!)
        input.handleSwipe(path: pts, keyMap: keyMap, fallbackKey: nil)
    }

    // MARK: Tests

    func testSentenceStartCapitalisesAndShiftDropsAfterLetter() {
        XCTAssertEqual(input.state.shift, .on)
        type("h")
        XCTAssertEqual(proxy.text, "H")
        XCTAssertEqual(input.state.shift, .off)
        type("allo. ")
        XCTAssertEqual(proxy.text, "Hallo. ")
        XCTAssertEqual(input.state.shift, .on)
    }

    func testAutocorrectOnSpaceAndBackspaceReverts() {
        type("hakko ")
        XCTAssertEqual(proxy.text, "Hallo ")
        input.handle(key: GermanLayouts.backspace)
        XCTAssertEqual(proxy.text, "Hakko")
        // The rejected correction is now remembered: typing it again keeps it.
        type(" ")
        XCTAssertEqual(proxy.text, "Hakko ")
    }

    func testNounCapitalisationMidSentence() {
        type("das haus ")
        XCTAssertEqual(proxy.text, "Das Haus ")
    }

    func testKnownLowercaseWordIsNotTouched() {
        type("wir essen ")
        XCTAssertEqual(proxy.text, "Wir essen ")
    }

    func testDoubleSpaceInsertsPeriod() {
        type("hallo  ")
        XCTAssertEqual(proxy.text, "Hallo. ")
        XCTAssertEqual(input.state.shift, .on)
    }

    func testSwipeCommitsWordWithAutoSpaceAndSmartPunctuation() {
        swipe("danke")
        XCTAssertEqual(proxy.text, "Danke ")
        XCTAssertEqual(input.state.suggestions.first { $0.kind == .primary }?.text, "Danke")
        type(".")
        XCTAssertEqual(proxy.text, "Danke. ")
        swipe("schön")
        XCTAssertEqual(proxy.text, "Danke. Schön ")
    }

    func testSwipeAfterTypedWordSeparatesWithSpace() {
        type("ich")
        swipe("habe")
        XCTAssertEqual(proxy.text, "Ich habe ")
    }

    func testSwipeAfterMistypedWordAutocorrectsIt() {
        type("hakko")
        swipe("welt")
        XCTAssertEqual(proxy.text, "Hallo Welt ")
    }

    func testSpaceAfterSwipeIsSwallowedAndBackspaceDeletesWholeWord() {
        swipe("morgen")
        type(" ")
        XCTAssertEqual(proxy.text, "Morgen ")
        swipe("danke")
        input.handle(key: GermanLayouts.backspace)   // right after a swipe: the whole word goes
        XCTAssertEqual(proxy.text, "Morgen ")
    }

    func testAlternateReplacesSwipedWord() {
        swipe("hallo")
        let alternates = input.state.suggestions.filter { $0.kind == .alternate }
        XCTAssertFalse(alternates.isEmpty)
        let alt = alternates[0]
        input.accept(alt)
        XCTAssertEqual(proxy.text, alt.text + " ")
    }

    func testCompletionSuggestionReplacesComposingWord() {
        type("wochene")
        let primary = input.state.suggestions.first { $0.text.lowercased().hasPrefix("wochene") && $0.text.count > 7 }
        XCTAssertNotNil(primary, "\(input.state.suggestions)")
        input.accept(primary!)
        XCTAssertEqual(proxy.text, "Wochenende ")
    }

    func testPredictionsAfterWord() {
        type("ich ")
        let texts = input.state.suggestions.map(\.text)
        XCTAssertEqual(input.state.suggestions.first?.kind, .prediction)
        XCTAssertTrue(texts.contains("habe") || texts.contains("bin"), "\(texts)")
    }

    func testComposingWordIgnoresCursorInsideWord() {
        type("hallo")
        proxy.cursor = 2
        input.textDidChangeExternally()
        XCTAssertEqual(input.composingWord, "")
        proxy.cursor = 5
        input.textDidChangeExternally()
        XCTAssertEqual(input.composingWord, "Hallo")
    }

    func testCapsLockAndShiftSlide() {
        input.lockShift()
        type("ab")
        XCTAssertEqual(proxy.text, "AB")
        XCTAssertEqual(input.state.shift, .locked)
        input.handle(key: GermanLayouts.shift)
        XCTAssertEqual(input.state.shift, .off)
        input.shiftSlide(to: key("c"))
        XCTAssertEqual(proxy.text, "ABC")
    }

    func testEmailFieldDisablesCorrectionsAndCapitalisation() {
        var traits = FieldTraits()
        traits.keyboardType = .emailAddress
        traits.autocapitalization = .none
        input.traits = traits
        input.refresh()
        XCTAssertEqual(input.state.shift, .off)
        type("hakko ")
        XCTAssertEqual(proxy.text, "hakko ")
        XCTAssertTrue(input.state.suggestions.isEmpty)
    }

    func testBackspaceRevertsAutocorrectTriggeredByPunctuation() {
        type("hakko.")
        XCTAssertEqual(proxy.text, "Hallo.")
        input.handle(key: GermanLayouts.backspace)
        XCTAssertEqual(proxy.text, "Hakko")
    }

    func testStaleAutoSpaceDoesNotSwallowARealSpace() {
        swipe("hallo")
        type(".")
        XCTAssertEqual(proxy.text, "Hallo. ")
        proxy.cursor = 5            // user moves the caret right after "Hallo"
        input.textDidChangeExternally()
        type(" ")
        XCTAssertEqual(proxy.text, "Hallo . ")
    }

    func testSwipeWithCaretInsideWordFallsBackToTap() {
        type("hallo")
        proxy.cursor = 3
        input.textDidChangeExternally()
        XCTAssertNil(input.previousWord)
        swipe("danke")
        XCTAssertFalse(proxy.text.contains("Danke"), proxy.text)
    }

    func testSwipeAfterOpeningBracketAddsNoSpace() {
        input.handle(key: Key(action: .character("("), label: "("))
        swipe("hallo")
        XCTAssertEqual(proxy.text, "(Hallo ")
    }

    func testBackspaceAfterSwipeThenSpaceDeletesOneCharacter() {
        swipe("morgen")
        type(" ")
        input.handle(key: GermanLayouts.backspace)
        XCTAssertEqual(proxy.text, "Morgen")
    }

    func testFieldWithoutAutocorrectionStillSwipesButNeverReplaces() {
        var traits = FieldTraits()
        traits.autocorrectionDisabled = true
        input.traits = traits
        input.refresh()
        type("hakko ")
        XCTAssertEqual(proxy.text, "Hakko ")                      // no silent replacement
        swipe("danke")
        XCTAssertEqual(proxy.text, "Hakko danke ")                // glide typing still works
        type("wochene")
        XCTAssertTrue(input.state.suggestions.contains { $0.text == "Wochenende" }, "\(input.state.suggestions)")
    }

    func testBackspaceRepeatDeletesWords() {
        type("hallo schöne welt")
        input.backspaceRepeat(wordwise: true)
        XCTAssertEqual(proxy.text, "Hallo schöne ")
        input.backspaceRepeat(wordwise: true)
        XCTAssertEqual(proxy.text, "Hallo ")
    }

    // MARK: Justin-Modus

    func testJustinModeReplacesEveryTypedWord() {
        settings.justinMode = true
        type("hallo welt.")
        XCTAssertEqual(proxy.text, "Justin Justin.")
        type(" essen ")
        XCTAssertEqual(proxy.text, "Justin Justin. Justin ")   // real words are replaced as well
    }

    func testJustinModeIgnoresAutocorrectToggle() {
        settings.justinMode = true
        settings.autocorrect = false
        type("hallo ")
        XCTAssertEqual(proxy.text, "Justin ")
    }

    func testJustinModeOffersNothingButJustin() {
        settings.justinMode = true
        type("hal")
        XCTAssertEqual(input.state.suggestions, [Suggestion(text: "Justin", kind: .primary)])
        input.accept(input.state.suggestions[0])
        XCTAssertEqual(proxy.text, "Justin ")
        XCTAssertEqual(input.state.suggestions, [Suggestion(text: "Justin", kind: .prediction)])
        input.accept(input.state.suggestions[0])
        XCTAssertEqual(proxy.text, "Justin Justin ")
        XCTAssertFalse(engine.user.isLearned("Justin"))
    }

    func testJustinModeBackspaceDoesNotRestoreTypedWord() {
        settings.justinMode = true
        type("hallo ")
        XCTAssertEqual(proxy.text, "Justin ")
        input.handle(key: GermanLayouts.backspace)
        XCTAssertEqual(proxy.text, "Justin")
        XCTAssertFalse(engine.user.isBlocked("Hallo"))
    }

    func testJustinModeAppliesToSwipeWithoutAlternates() {
        settings.justinMode = true
        swipe("danke")
        XCTAssertEqual(proxy.text, "Justin ")
        XCTAssertEqual(input.state.suggestions, [Suggestion(text: "Justin", kind: .prediction)])
        input.accept(input.state.suggestions[0])
        XCTAssertEqual(proxy.text, "Justin ")
    }

    func testJustinModeFollowsCapsLock() {
        settings.justinMode = true
        input.lockShift()
        type("hallo ")
        XCTAssertEqual(proxy.text, "JUSTIN ")
    }

    func testJustinModeAppliesInEveryField() {
        settings.justinMode = true
        var traits = FieldTraits()
        traits.autocorrectionDisabled = true
        input.traits = traits
        input.refresh()
        type("hallo ")
        XCTAssertEqual(proxy.text, "Justin ")

        var email = FieldTraits()
        email.keyboardType = .emailAddress
        email.autocapitalization = .none
        input.traits = email
        input.refresh()
        type("welt ")
        XCTAssertEqual(proxy.text, "Justin Justin ")
    }

    func testJustinModeWorksBeforeTheLexiconIsLoaded() {
        settings.justinMode = true
        input.engine = nil
        type("hallo ")
        XCTAssertEqual(proxy.text, "Justin ")
    }

    // MARK: Dynamic hit targets

    func testLetterPriorFollowsTheComposingWord() {
        XCTAssertNotNil(input.state.letterPrior, "word start: first-letter distribution")
        type("Hall")
        XCTAssertEqual(input.state.letterPrior?.mostLikely, "o")
        type("o ")
        // After a complete word the prior comes from the bigram context, not the typed letters.
        XCTAssertNotNil(input.state.letterPrior)
        XCTAssertNotEqual(input.state.letterPrior?.mostLikely, "o")
    }

    func testLetterPriorIsOffWhenDisabledOrUnavailable() {
        settings.smartHitTargets = false
        input.refresh()
        XCTAssertNil(input.state.letterPrior)
        settings.smartHitTargets = true

        var secure = FieldTraits()
        secure.isSecure = true
        input.traits = secure
        XCTAssertNil(input.state.letterPrior, "no prior in password fields")
        input.traits = FieldTraits()
        XCTAssertNotNil(input.state.letterPrior)

        input.handle(key: GermanLayouts.toSymbols)
        XCTAssertNil(input.state.letterPrior, "symbols layer has no letter keys")
        input.handle(key: GermanLayouts.toLetters)

        // Cursor inside a word: the prefix isn't the word being typed.
        type("Hallo")
        proxy.moveCursor(by: -2)
        input.textDidChangeExternally()
        XCTAssertNil(input.state.letterPrior)
    }
}

final class WalkthroughReplayTests: XCTestCase {
    func testWalkthroughSentence() {
        let suite = UserDefaults(suiteName: "walk-\(UUID())")!
        let settings = KeyboardSettings(defaults: suite)
        let proxy = FakeTextProxy()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("walk-\(UUID()).json")
        let engine = KeyboardEngine(lexicon: InputControllerTests.lexicon, user: UserLexicon(fileURL: url))
        let input = InputController(engine: engine, settings: settings, proxy: proxy)
        input.keyMap = KeyMap.reference()
        input.traits = FieldTraits()
        input.refresh()
        let letters = GermanLayouts.letters()
        func type(_ s: String) {
            for c in s {
                switch c {
                case " ": input.handle(key: GermanLayouts.space)
                case ".": input.handle(key: GermanLayouts.period)
                default: input.handle(key: letters.allKeys.first { $0.character == c && $0.isLetter }!)
                }
            }
        }
        type("ich habe morgen einen termin ")
        XCTAssertEqual(proxy.text, "Ich habe morgen einen Termin ")
        type("in koeln  ")
        XCTAssertEqual(proxy.text, "Ich habe morgen einen Termin in Köln. ")
        type("dnake ")
        XCTAssertEqual(proxy.text, "Ich habe morgen einen Termin in Köln. Danke ")
        let corrections = engine.autocorrect(for: KeyMap.reference()).corrections(for: "hakko", previousWord: "Danke", isSentenceStart: false)
        print("WALK-CORRECTIONS \(corrections.map { "\($0.word):\($0.distance):\($0.score):\($0.autoApply)" })")
        type("hakko ")
        XCTAssertEqual(proxy.text, "Ich habe morgen einen Termin in Köln. Danke hallo ")
    }

    // MARK: Comma / emoji key

    private final class DelegateRecorder: InputControllerDelegate {
        var emojiRequests = 0
        func inputController(_ c: InputController, didUpdate state: InputUIState) {}
        func inputControllerRequestsGlobe(_ c: InputController) {}
        func inputControllerRequestsEmoji(_ c: InputController) { emojiRequests += 1 }
        func inputControllerRequestsDismiss(_ c: InputController) {}
    }

    func testCommaKeyTypesCommaOnTapAndOpensEmojiOnHold() {
        let recorder = DelegateRecorder()
        input.delegate = recorder
        let comma = GermanLayouts.letters(options: LayoutOptions(needsGlobeKey: false)).rows[3].keys.first { $0.id == "comma" }!
        type("ja")
        input.handle(key: comma)
        XCTAssertEqual(proxy.text, "ja,")
        XCTAssertEqual(recorder.emojiRequests, 0)

        input.handleLongPress(key: comma)
        XCTAssertEqual(recorder.emojiRequests, 1)
        XCTAssertEqual(proxy.text, "ja,", "the hold must not type a second comma")

        // Keys without a hold action are ignored.
        input.handleLongPress(key: GermanLayouts.space)
        XCTAssertEqual(recorder.emojiRequests, 1)
        XCTAssertEqual(proxy.text, "ja,")
    }

}
