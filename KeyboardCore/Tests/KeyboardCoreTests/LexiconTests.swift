import XCTest
@testable import KeyboardCore

final class LexiconTests: XCTestCase {
    let lex = TestSupport.lexicon

    func testLoadsAndIsFrequencyOrdered() {
        XCTAssertGreaterThan(lex.count, 100_000)
        XCTAssertEqual(lex.word(0), "ich")
        XCTAssertTrue(lex.contains("Haus"))
        XCTAssertTrue(lex.contains("Zeit"))
        XCTAssertTrue(lex.contains("Straße"))
        XCTAssertFalse(lex.contains("haus"))
        XCTAssertTrue(lex.containsIgnoringCase("haus"))
        XCTAssertEqual(lex.casings(of: "sie").count, 2)
    }

    func testShippedFileIsSortedForBinarySearch() {
        XCTAssertTrue(lex.isSortedForBinarySearch())
        XCTAssertEqual(lex.id(exact: "Haus"), lex.id(caseInsensitive: "HAUS"))
        XCTAssertNil(lex.id(exact: "haus"))
        XCTAssertEqual(lex.casings(of: "sie"), ["sie", "Sie"])
    }

    func testCompletions() {
        let ids = lex.completions(prefix: "hau", limit: 5).map(lex.word)
        XCTAssertTrue(ids.contains("Haus"), "\(ids)")
        XCTAssertTrue(lex.completions(prefix: "xyzq", limit: 5).isEmpty)
    }

    func testBigrams() {
        let next = lex.successors(of: "ich").prefix(3).map(\.word)
        XCTAssertTrue(next.contains("habe") || next.contains("bin"), "\(next)")
        XCTAssertNotNil(lex.bigramLogProb(previous: lex.id(exact: "guten")!, next: lex.id(exact: "Morgen")!))
    }

    func testLoadTimeIsAcceptable() {
        measure { _ = try? Lexicon.loadBundled() }
    }
}
