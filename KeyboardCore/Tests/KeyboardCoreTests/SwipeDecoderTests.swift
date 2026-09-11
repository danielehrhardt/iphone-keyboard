import XCTest
@testable import KeyboardCore

final class SwipeDecoderTests: XCTestCase {
    let lex = TestSupport.lexicon
    lazy var decoder = SwipeDecoder(lexicon: lex)
    let km = TestSupport.keyMap

    func decodeTop(_ word: String, jitter: CGFloat = 0, seed: UInt64 = 1, previous: String? = nil, overshoot: CGFloat = 0) -> [String] {
        let path = TestSupport.syntheticPath(for: word, jitter: jitter, seed: seed, overshootEnd: overshoot)
        return decoder.decode(path: path, keyMap: km, context: DecodeContext(previousWord: previous), limit: 4).map(\.word)
    }

    func testCleanPathsDecodeToTheWord() {
        for w in ["hallo", "danke", "morgen", "schön", "können", "Straße", "wir", "Zeit", "vielleicht", "Wochenende", "gut", "ja"] {
            let top = decodeTop(w)
            XCTAssertEqual(top.first?.lowercased(), w.lowercased(), "expected \(w), got \(top)")
        }
    }

    func testJitteredPathsStayRobust() {
        var hits = 0, total = 0
        let words = ["hallo", "danke", "heute", "morgen", "schön", "machen", "kommen", "Freunde", "Arbeit", "wirklich",
                     "zusammen", "eigentlich", "natürlich", "Familie", "Problem", "später", "Woche", "Leben", "Kinder", "essen"]
        for w in words {
            for seed in 1...5 {
                total += 1
                let top = decodeTop(w, jitter: km.keyWidth * 0.35, seed: UInt64(seed))
                if top.first?.lowercased() == w.lowercased() { hits += 1 }
                else if top.prefix(3).map({ $0.lowercased() }).contains(w.lowercased()) { hits += 0 }
            }
        }
        let rate = Double(hits) / Double(total)
        XCTAssertGreaterThan(rate, 0.85, "top-1 rate \(rate)")
    }

    func testOvershootAtTheEndIsForgiven() {
        let top = decodeTop("hallo", overshoot: km.keyWidth * 0.6)
        XCTAssertEqual(top.first?.lowercased(), "hallo", "\(top)")
    }

    func testContextBreaksTies() {
        // "Sie" vs "sie": after "können" the formal form should win.
        let top = decodeTop("sie", previous: "können")
        XCTAssertEqual(top.first, "Sie", "\(top)")
    }

    func testTapIsNotASwipe() {
        let p = km.centers[Int(KeyAlphabet.code(for: "a")!)]
        let path = [p, CGPoint(x: p.x + 2, y: p.y + 1), CGPoint(x: p.x + 3, y: p.y + 2)]
        XCTAssertTrue(decoder.decode(path: path, keyMap: km).isEmpty)
    }

    func testDecodePerformance() {
        let path = TestSupport.syntheticPath(for: "wahrscheinlich", jitter: 3)
        measure { _ = decoder.decode(path: path, keyMap: km) }
    }
}
