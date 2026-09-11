import XCTest
@testable import KeyboardCore

final class PredictorAndRulesTests: XCTestCase {
    let lex = TestSupport.lexicon
    lazy var predictor = Predictor(lexicon: lex)

    func testNextWordsAfterCommonWord() {
        let next = predictor.nextWords(after: "ich", isSentenceStart: false)
        XCTAssertEqual(next.count, 3)
        XCTAssertTrue(next.contains("habe") || next.contains("bin"), "\(next)")
    }

    func testCompletionsRespectCase() {
        XCTAssertEqual(predictor.completions(prefix: "hau", previous: nil, isSentenceStart: false).first, "Haus")
        XCTAssertEqual(predictor.completions(prefix: "Wo", previous: nil, isSentenceStart: false).first?.first?.isUppercase, true)
        XCTAssertEqual(predictor.completions(prefix: "un", previous: nil, isSentenceStart: true).first, "Und")
    }

    func testSentenceStartDetection() {
        XCTAssertTrue(GermanRules.isSentenceStart(""))
        XCTAssertTrue(GermanRules.isSentenceStart("Hallo. "))
        XCTAssertTrue(GermanRules.isSentenceStart("Was? "))
        XCTAssertTrue(GermanRules.isSentenceStart("Zeile\n"))
        XCTAssertFalse(GermanRules.isSentenceStart("Hallo "))
        XCTAssertFalse(GermanRules.isSentenceStart("Hallo"))
        XCTAssertFalse(GermanRules.isSentenceStart("z.B. "))
        XCTAssertFalse(GermanRules.isSentenceStart("3.5 "))
        XCTAssertFalse(GermanRules.isSentenceStart("Hallo."))   // no space yet → still composing
        XCTAssertTrue(GermanRules.isSentenceStart("Das war es. "))
        XCTAssertTrue(GermanRules.isSentenceStart("Ich bin ok. "))
        XCTAssertTrue(GermanRules.isSentenceStart("Hallo Welt.\u{00A0}"))
        XCTAssertFalse(GermanRules.isSentenceStart("Peter A. "))
        XCTAssertFalse(GermanRules.isSentenceStart("d.h. "))
        XCTAssertTrue(GermanRules.isSentenceStart("("))
        XCTAssertTrue(GermanRules.isSentenceStart("Er sagte: „"))
        XCTAssertFalse(GermanRules.isSentenceStart("Er sagte („"))
    }

    func testUmlautVariants() {
        XCTAssertTrue(GermanRules.umlautVariants(of: "schoen").contains("schön"))
        XCTAssertTrue(GermanRules.umlautVariants(of: "Fuesse").contains("Füße"))
        XCTAssertTrue(GermanRules.umlautVariants(of: "Wasser").contains("Waßer"))
    }

    func testUserLexiconLearning() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ul-\(UUID()).json")
        let ul = UserLexicon(fileURL: url)
        ul.learn(word: "Codext", after: "bei")
        XCTAssertFalse(ul.isLearned("Codext"))
        ul.learn(word: "Codext", after: "bei")
        XCTAssertTrue(ul.isLearned("Codext"))
        XCTAssertEqual(ul.successors(of: "bei").first?.word, "Codext")
        ul.saveNow()
        let reloaded = UserLexicon(fileURL: url)
        XCTAssertTrue(reloaded.isLearned("Codext"))
        reloaded.remove(word: "Codext")
        XCTAssertTrue(reloaded.isBlocked("Codext"))
        ul.learn(word: "hunter2ABCdef", after: nil)
        XCTAssertNil(ul.unigramLogBoost("hunter2ABCdef"))
    }
}
