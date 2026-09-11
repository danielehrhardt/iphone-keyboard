import XCTest
@testable import KeyboardCore

final class AutocorrectTests: XCTestCase {
    let lex = TestSupport.lexicon
    lazy var ac = Autocorrect(lexicon: lex, keyMap: TestSupport.keyMap)

    func best(_ typed: String, previous: String? = nil, start: Bool = false) -> Correction? {
        ac.corrections(for: typed, previousWord: previous, isSentenceStart: start).first
    }

    func testAdjacentKeyTypos() {
        XCTAssertEqual(best("hakko")?.word, "hallo")           // k next to l
        XCTAssertEqual(best("hakko")?.autoApply, true)
        XCTAssertEqual(best("dnake")?.word.lowercased(), "danke")   // transposition
        XCTAssertEqual(best("morgem")?.word, "morgen")
    }

    func testCapitalisesGermanNouns() {
        let c = best("haus")
        XCTAssertEqual(c?.word, "Haus")
        XCTAssertEqual(c?.autoApply, true)
        // "essen" is a valid lowercase verb – never force the noun.
        XCTAssertEqual(best("essen")?.autoApply, false)
    }

    func testSentenceStartCapitalIsNotUndone() {
        XCTAssertEqual(best("Wir", start: true)?.autoApply, false)
        XCTAssertEqual(best("Das", start: true)?.autoApply, false)
        XCTAssertEqual(best("Das", start: true)?.word, "Das")
        let c = best("Hakko", start: true)
        XCTAssertEqual(c?.word.lowercased(), "hallo", "\(String(describing: c))")
        XCTAssertEqual(c?.autoApply, true)
    }

    func testDeliberateAccentsAreKept() {
        XCTAssertEqual(best("Má")?.autoApply ?? false, false)
        XCTAssertEqual(best("café")?.autoApply ?? false, false)
        XCTAssertEqual(best("Zoë")?.autoApply ?? false, false)
    }

    func testUmlautDigraphs() {
        XCTAssertEqual(best("schoen")?.word, "schön")
        XCTAssertEqual(best("strasse")?.word, "Straße")
        XCTAssertEqual(best("fuer")?.word, "für")
    }

    func testKnownWordsAreLeftAlone() {
        XCTAssertEqual(best("Zeit")?.autoApply, false)
        XCTAssertEqual(best("und")?.autoApply, false)
        XCTAssertEqual(best("ok")?.autoApply, false)
    }

    func testShortUnknownWordsAreNotForced() {
        // two-letter tokens are too ambiguous to auto-replace
        XCTAssertEqual(best("xq")?.autoApply ?? false, false)
    }

    func testPerformance() {
        measure { _ = ac.corrections(for: "wahrscheinlihc", previousWord: "ist", isSentenceStart: false) }
    }
}
