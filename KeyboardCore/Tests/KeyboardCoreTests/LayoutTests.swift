import XCTest
@testable import KeyboardCore

final class LayoutTests: XCTestCase {
    func testGermanLettersLayoutHasAllLetters() {
        let layout = GermanLayouts.letters()
        let letters = Set(layout.letterKeys.compactMap(\.character))
        for c in KeyAlphabet.letters { XCTAssertTrue(letters.contains(c), "missing \(c)") }
        XCTAssertEqual(layout.rows[0].keys.map(\.label).joined(), "qwertzuiopü")
        XCTAssertEqual(layout.rows[1].keys.map(\.label).joined(), "asdfghjklöä")
        XCTAssertEqual(layout.rows[2].keys.filter(\.isLetter).map(\.label).joined(), "yxcvbnm")
    }

    func testGeometryFitsWidthAndSpaceBarStretches() {
        let g = KeyboardGeometry(layout: GermanLayouts.letters(), size: CGSize(width: 390, height: 216))
        for kf in g.keyFrames {
            XCTAssertGreaterThanOrEqual(kf.frame.minX, 0)
            XCTAssertLessThanOrEqual(kf.frame.maxX, 390.5)
        }
        let space = g.keyFrame(for: GermanLayouts.space)!
        XCTAssertGreaterThan(space.frame.width, g.unitWidth * 3)
        XCTAssertNotNil(g.keyFrame(at: CGPoint(x: 1, y: 1)))
        XCTAssertEqual(g.keyFrame(at: CGPoint(x: 20, y: 30))?.key.label, "q")
    }

    func testCommaKeySitsLeftOfSpaceAndCanBeDisabled() {
        let bottom = GermanLayouts.letters().rows[3].keys
        let space = bottom.firstIndex { $0.action == .space }!
        XCTAssertEqual(bottom[space - 1].id, "comma")
        XCTAssertEqual(bottom[space - 1].action, .character(","))

        let without = GermanLayouts.letters(options: LayoutOptions(showsCommaKey: false)).rows[3].keys
        XCTAssertFalse(without.contains { $0.id == "comma" })

        // E-mail fields keep "@" left of the space bar instead.
        let email = GermanLayouts.letters(options: LayoutOptions(isEmailOrURL: true)).rows[3].keys
        XCTAssertFalse(email.contains { $0.id == "comma" })
        XCTAssertEqual(email[email.firstIndex { $0.action == .space }! - 1].id, "at")

        // The bottom row is shared, so the symbol layers get the key too.
        XCTAssertTrue(GermanLayouts.symbols().rows[3].keys.contains { $0.id == "comma" })
    }

    func testKeyMapNearest() {
        let km = KeyMap.reference()
        let q = km.centers[Int(KeyAlphabet.code(for: "q")!)]
        let near = km.nearestCodes(to: q, radius: km.keyWidth * 1.5, limit: 4)
        XCTAssertEqual(near.first?.code, KeyAlphabet.code(for: "q"))
        XCTAssertTrue(km.areAdjacent(KeyAlphabet.code(for: "q")!, KeyAlphabet.code(for: "a")!))
        XCTAssertFalse(km.areAdjacent(KeyAlphabet.code(for: "q")!, KeyAlphabet.code(for: "p")!))
    }

    func testSwipeCodesCollapseDuplicatesAndFoldSharpS() {
        XCTAssertEqual(KeyAlphabet.swipeCodes("Hallo"), KeyAlphabet.codes("halo"))
        XCTAssertEqual(KeyAlphabet.codes("Straße"), KeyAlphabet.codes("strase"))
        XCTAssertEqual(KeyAlphabet.code(for: "é"), KeyAlphabet.code(for: "e"))
    }
}
