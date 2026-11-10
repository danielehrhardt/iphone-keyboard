import XCTest
import CoreGraphics
@testable import KeyboardCore

/// The split keyboard for the iPhone Duo's inner display held sideways (951 pt wide).
final class SplitLayoutTests: XCTestCase {
    private let size = CGSize(width: 951, height: 236)

    private func geometry(_ layer: KeyboardLayer = .letters, options: LayoutOptions = LayoutOptions(), split: Bool = true) -> KeyboardGeometry {
        KeyboardGeometry(layout: KeyboardLayouts.layout(for: layer, options: options), size: size,
                         metrics: .unfoldedLandscape(width: size.width, split: split))
    }

    func testNoKeyLiesOnTheFold() {
        for language in KeyboardLanguage.allCases {
            for layer in [KeyboardLayer.letters, .symbols, .extraSymbols] {
                let g = geometry(layer, options: LayoutOptions(language: language))
                XCTAssertTrue(g.isSplit)
                let fold = size.width / 2
                for kf in g.keyFrames {
                    XCTAssertFalse(kf.frame.minX < fold + 40 && kf.frame.maxX > fold - 40,
                                   "\(language) \(layer): \(kf.key.id) covers the fold at \(kf.frame)")
                }
            }
        }
    }

    func testEachHalfHasASpaceBar() {
        let spaces = geometry().keyFrames.filter { $0.key.action == .space }
        XCTAssertEqual(spaces.map(\.key.id).sorted(), ["space", KeyboardGeometry.splitSpaceID].sorted())
        XCTAssertLessThan(spaces[0].frame.maxX, size.width / 2)
        XCTAssertGreaterThan(spaces[1].frame.minX, size.width / 2)
        XCTAssertGreaterThan(min(spaces[0].frame.width, spaces[1].frame.width), 100)
    }

    func testGermanRowsBreakLikeAThumbKeyboard() {
        let g = geometry()
        let mid = size.width / 2
        let left = Set(g.keyFrames.filter { $0.key.isLetter && $0.center.x < mid }.compactMap(\.key.character))
        XCTAssertTrue(Set("qwertasdfgyxc").isSubset(of: left), "left half: \(left.sorted())")
        XCTAssertTrue(left.isDisjoint(with: Set("zuiopühjklöäbnm")), "left half: \(left.sorted())")
        XCTAssertEqual(g.letterCenters.count, KeyboardLayouts.letters().letterKeys.count, "every letter keeps its key")
    }

    func testKeysStayThumbSizedAndUnique() {
        let g = geometry()
        XCTAssertGreaterThan(g.unitWidth, 44)
        XCTAssertLessThan(g.unitWidth, 64)
        XCTAssertEqual(Set(g.keyFrames.map(\.key.id)).count, g.keyFrames.count)
    }

    func testEveryTouchFindsAKey() {
        let g = geometry()
        for x in stride(from: 0, through: size.width, by: 7) {
            for y in stride(from: 0, through: size.height, by: 7) {
                XCTAssertNotNil(g.keyFrame(at: CGPoint(x: x, y: y)))
            }
        }
        let t = g.keyFrames.first { $0.key.character == "t" }!.frame
        let z = g.keyFrames.first { $0.key.character == "z" }!.frame
        XCTAssertEqual(g.keyFrame(at: CGPoint(x: t.maxX + 15, y: t.midY))?.key.character, "t", "a touch in the gap goes to the nearest key")
        XCTAssertEqual(g.keyFrame(at: CGPoint(x: z.minX - 15, y: z.midY))?.key.character, "z")
    }

    func testNumberPadsAndSettingOffStayInOneBlock() {
        XCTAssertFalse(geometry(.numberPad).isSplit)
        XCTAssertFalse(geometry(split: false).isSplit)
        XCTAssertEqual(geometry(split: false).keyFrames.filter { $0.key.action == .space }.count, 1)
    }
}
