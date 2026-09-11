import XCTest
import CoreGraphics
@testable import KeyboardCore

/// English support and the language plumbing: layout, key map folding, dictionary, rules,
/// autocorrect, swipe decoding and the language settings.
final class LanguageTests: XCTestCase {
    static let english: Lexicon = {
        do { return try Lexicon.loadBundled(language: .english) } catch { fatalError("english lexicon: \(error)") }
    }()
    let english = LanguageTests.english
    let keyMap = KeyMap.reference(language: .english)

    // MARK: Layout

    func testEnglishLettersLayoutIsQwerty() {
        let layout = EnglishLayouts.letters()
        XCTAssertEqual(layout.rows[0].keys.map(\.label).joined(), "qwertyuiop")
        XCTAssertEqual(layout.rows[1].keys.map(\.label).joined(), "asdfghjkl")
        XCTAssertEqual(layout.rows[2].keys.filter(\.isLetter).map(\.label).joined(), "zxcvbnm")
        XCTAssertEqual(layout.rows[1].leadingInset, 0.5)
        XCTAssertEqual(layout.columns, 10)
        let letters = Set(layout.letterKeys.compactMap(\.character))
        for c in KeyAlphabet.letters.prefix(KeyAlphabet.baseCount) { XCTAssertTrue(letters.contains(c), "missing \(c)") }
        XCTAssertFalse(letters.contains("ü"))
        // Umlauts are reached by holding the base letter.
        XCTAssertTrue(layout.letterKeys.first { $0.character == "u" }!.alternates.contains("ü"))
        XCTAssertEqual(layout.rows[3].keys.first { $0.action == .space }?.label, "space")
    }

    func testLanguageDispatchAndSpaceLabel() {
        XCTAssertEqual(KeyboardLanguage.german.layout(for: .letters).columns, 11)
        XCTAssertEqual(KeyboardLanguage.english.layout(for: .letters).columns, 10)
        XCTAssertEqual(KeyboardLayouts.letters(options: LayoutOptions(language: .english)).rows[0].keys[5].label, "y")
        XCTAssertEqual(KeyboardLayouts.letters(options: LayoutOptions(language: .german)).rows[0].keys[5].label, "z")

        let named = KeyboardLayouts.letters(options: LayoutOptions(language: .english, showsLanguageName: true))
        XCTAssertEqual(named.rows[3].keys.first { $0.action == .space }?.label, "English")
        let german = KeyboardLayouts.letters(options: LayoutOptions(language: .german, showsLanguageName: true))
        XCTAssertEqual(german.rows[3].keys.first { $0.action == .space }?.label, "Deutsch")
        XCTAssertEqual(GermanLayouts.letters().rows[3].keys.first { $0.action == .space }?.label, "Leerzeichen")

        // The symbol layers differ only in the currency key.
        XCTAssertEqual(EnglishLayouts.symbols().rows[1].keys[6].label, "$")
        XCTAssertEqual(GermanLayouts.symbols().rows[1].keys[6].label, "€")
        XCTAssertEqual(EnglishLayouts.layout(for: .decimalPad).rows[3].keys[0].label, ".")
        XCTAssertEqual(GermanLayouts.layout(for: .decimalPad).rows[3].keys[0].label, ",")
    }

    func testEnglishKeyIDsAreUniqueAndRowEdgesMatchTheSystemKeyboard() {
        for layer in KeyboardLayer.allCases {
            let ids = EnglishLayouts.layout(for: layer).allKeys.map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "duplicate key id in \(layer)")
        }
        let width: CGFloat = 390
        let metrics = KeyboardGeometry.Metrics.phonePortrait
        let g = KeyboardGeometry(layout: EnglishLayouts.letters(), size: CGSize(width: width, height: 216))
        let row = g.layout.rows[2]
        let first = g.keyFrame(for: row.keys.first!)!, last = g.keyFrame(for: row.keys.last!)!
        XCTAssertEqual(first.frame.minX, metrics.sideInset, accuracy: 0.5)
        XCTAssertEqual(last.frame.maxX, width - metrics.sideInset, accuracy: 0.5)
        // Shift and backspace keep a wider gap to the letters, like Apple's English keyboard.
        XCTAssertGreaterThan(g.keyFrame(for: row.keys[1])!.frame.minX - first.frame.maxX, g.horizontalGap + 1)
        // The home row is inset by half a key on both sides.
        let a = g.keyFrame(for: g.layout.rows[1].keys.first!)!, q = g.keyFrame(for: g.layout.rows[0].keys.first!)!
        XCTAssertEqual(a.frame.minX - q.frame.minX, (g.unitWidth + g.horizontalGap) / 2, accuracy: 0.5)
    }

    // MARK: Key map

    func testQwertyKeyMapFoldsUmlautsOntoBaseKeys() {
        let a = keyMap.centers[Int(KeyAlphabet.code(for: "a")!)]
        XCTAssertEqual(keyMap.centers[Int(KeyAlphabet.code(for: "ä")!)], a)
        XCTAssertEqual(keyMap.centers[Int(KeyAlphabet.code(for: "ö")!)], keyMap.centers[Int(KeyAlphabet.code(for: "o")!)])
        XCTAssertEqual(keyMap.centers[Int(KeyAlphabet.code(for: "ü")!)], keyMap.centers[Int(KeyAlphabet.code(for: "u")!)])
        XCTAssertEqual(KeyAlphabet.baseCode(for: KeyAlphabet.code(for: "ä")!), KeyAlphabet.code(for: "a"))
        XCTAssertNil(KeyAlphabet.baseCode(for: KeyAlphabet.code(for: "a")!))
        // Adjacency follows the QWERTY arrangement: y sits next to t and u.
        XCTAssertTrue(keyMap.areAdjacent(KeyAlphabet.code(for: "y")!, KeyAlphabet.code(for: "t")!))
        XCTAssertFalse(keyMap.areAdjacent(KeyAlphabet.code(for: "z")!, KeyAlphabet.code(for: "t")!))
        // A layout missing a base letter has no key map.
        let broken = KeyboardLayout(layer: .letters, rows: [KeyRow(GermanLayouts.letterRows[0])], columns: 11)
        XCTAssertNil(KeyMap(geometry: KeyboardGeometry(layout: broken, size: CGSize(width: 390, height: 216))))
    }

    // MARK: Dictionary

    func testEnglishLexiconLoads() {
        XCTAssertEqual(english.language, .english)
        XCTAssertGreaterThan(english.count, 80_000)
        XCTAssertTrue(english.isSortedForBinarySearch())
        XCTAssertEqual(english.word(0), "the")
        XCTAssertTrue(english.contains("I"))
        XCTAssertFalse(english.contains("i"))
        XCTAssertTrue(english.contains("don't"))
        XCTAssertTrue(english.contains("hello"))
        XCTAssertTrue(english.contains("London"))
        XCTAssertFalse(english.containsIgnoringCase("teh"))
        XCTAssertTrue(english.completions(prefix: "hel", limit: 10).map(english.word).contains("hello"))
        let next = english.successors(of: "I").prefix(5).map(\.word)
        XCTAssertTrue(next.contains("think") || next.contains("was") || next.contains("am") || next.contains("have"), "\(next)")
    }

    func testGermanLexiconIsUnchanged() {
        XCTAssertEqual(TestSupport.lexicon.language, .german)
        XCTAssertEqual(try Lexicon.loadBundled().language, .german)
    }

    // MARK: Rules

    func testEnglishSentenceRules() {
        let rules = LanguageRules.english
        XCTAssertTrue(rules.isSentenceStart(""))
        XCTAssertTrue(rules.isSentenceStart("Hello. "))
        XCTAssertTrue(rules.isSentenceStart("Really? "))
        XCTAssertFalse(rules.isSentenceStart("Mr. "))
        XCTAssertFalse(rules.isSentenceStart("e.g. "))
        XCTAssertFalse(rules.isSentenceStart("3.5 "))
        XCTAssertFalse(rules.isSentenceStart("Hello"))
        // "z.B." is German; in English it is an unknown abbreviation but still contains a period.
        XCTAssertFalse(rules.isSentenceStart("z.B. "))
        // "usw." is only an abbreviation in German.
        XCTAssertTrue(rules.isSentenceStart("usw. "))
        XCTAssertFalse(LanguageRules.german.isSentenceStart("usw. "))
        XCTAssertTrue(rules.spellingVariants("schoen").isEmpty)
        XCTAssertEqual(LanguageRules.german.spellingVariants("schoen"), GermanRules.umlautVariants(of: "schoen"))
        XCTAssertEqual(KeyboardLanguage.english.rules.coldStartWords.first, "I")
    }

    // MARK: Engines

    func testEnglishPredictorAndAutocorrect() {
        let predictor = Predictor(lexicon: english)
        XCTAssertEqual(predictor.nextWords(after: nil, isSentenceStart: true).first, "I")
        XCTAssertTrue(predictor.completions(prefix: "tha", previous: nil, isSentenceStart: false).contains("that"))

        let ac = Autocorrect(lexicon: english, keyMap: keyMap)
        func best(_ typed: String, previous: String? = nil, sentenceStart: Bool = false) -> Correction? {
            ac.corrections(for: typed, previousWord: previous, isSentenceStart: sentenceStart).first
        }
        XCTAssertEqual(best("teh")?.word, "the")
        XCTAssertEqual(best("teh")?.autoApply, true)
        XCTAssertEqual(best("i")?.word, "I")
        XCTAssertEqual(best("i")?.autoApply, true)
        XCTAssertEqual(best("dont")?.word, "don't")
        XCTAssertEqual(best("dont")?.autoApply, true)
        // Real words stay.
        XCTAssertEqual(best("hello")?.word, "hello")
        XCTAssertEqual(best("hello")?.autoApply, false)
        // No German digraph magic in English: "schoen" is simply unknown.
        XCTAssertNotEqual(best("schoen")?.word, "schön")
    }

    func testEnglishSwipeDecoding() {
        let decoder = SwipeDecoder(lexicon: english)
        for word in ["hello", "you", "thanks", "world"] {
            let path = TestSupport.syntheticPath(for: word, keyMap: keyMap, jitter: 3)
            let result = decoder.decode(path: path, keyMap: keyMap, limit: 3)
            XCTAssertEqual(result.first?.word.lowercased(), word, "\(result.map(\.word))")
        }
    }

    func testEnginePerLanguage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lang-\(UUID()).json")
        let engine = KeyboardEngine(lexicon: english, user: UserLexicon(fileURL: url))
        XCTAssertEqual(engine.language, .english)
        XCTAssertEqual(engine.decodeSwipe(path: TestSupport.syntheticPath(for: "hello", keyMap: keyMap), keyMap: keyMap, previousWord: nil).first?.word, "hello")
        XCTAssertEqual(KeyboardLanguage.english.userLexiconFileName, "user-lexicon-en.json")
        XCTAssertEqual(KeyboardLanguage.german.userLexiconFileName, "user-lexicon.json")
    }

    // MARK: Settings

    func testLanguageSettingsNeverLeaveTheKeyboardWithoutALanguage() {
        let settings = KeyboardSettings(defaults: UserDefaults(suiteName: "lang-tests-\(UUID())")!)
        XCTAssertEqual(settings.enabledLanguages, [.german])
        XCTAssertEqual(settings.currentLanguage, .german)
        XCTAssertFalse(settings.hasMultipleLanguages)

        settings.setLanguage(.english, enabled: true)
        XCTAssertEqual(settings.enabledLanguages, [.german, .english])
        XCTAssertTrue(settings.hasMultipleLanguages)
        XCTAssertEqual(settings.nextLanguage(after: .german), .english)
        XCTAssertEqual(settings.nextLanguage(after: .english), .german)

        settings.currentLanguage = .english
        XCTAssertEqual(settings.currentLanguage, .english)
        settings.setLanguage(.english, enabled: false)
        XCTAssertEqual(settings.enabledLanguages, [.german])
        XCTAssertEqual(settings.currentLanguage, .german, "a disabled language cannot stay current")

        settings.setLanguage(.german, enabled: false)
        XCTAssertEqual(settings.enabledLanguages, [.german], "the last language stays on")
        settings.enabledLanguages = []
        XCTAssertEqual(settings.enabledLanguages, [.german])
        settings.enabledLanguages = [.english, .english, .german]
        XCTAssertEqual(settings.enabledLanguages, [.english, .german])
        XCTAssertEqual(settings.currentLanguage, .english, "a stored current language that is no longer enabled falls back to the first enabled one")
    }
}
