import XCTest
@testable import KeyboardCore

final class LetterPriorTests: XCTestCase {
    let lex = TestSupport.lexicon
    lazy var predictor = Predictor(lexicon: lex)
    let geometry = KeyboardGeometry(layout: GermanLayouts.letters(), size: CGSize(width: 390, height: 216))

    // MARK: Prior

    func testPriorFollowsDictionaryCompletions() throws {
        let prior = try XCTUnwrap(predictor.letterPrior(prefix: "Hall", previous: nil))
        XCTAssertEqual(prior.mostLikely, "o", "Hallo / Halle dominate")
        XCTAssertGreaterThan(prior.probability(of: "o"), prior.probability(of: "q") * 10)
        XCTAssertEqual(prior.probabilities.reduce(0, +), 1, accuracy: 0.001)
        XCTAssertTrue(prior.probabilities.allSatisfy { $0 > 0 }, "smoothing keeps every letter possible")
    }

    func testPriorAtWordStartUsesFirstLetters() throws {
        let prior = try XCTUnwrap(predictor.letterPrior(prefix: "", previous: nil))
        XCTAssertGreaterThan(prior.probability(of: "d"), prior.probability(of: "q"))
        XCTAssertGreaterThan(prior.probability(of: "s"), prior.probability(of: "y"))
    }

    func testPriorUsesBigramContext() throws {
        let cold = try XCTUnwrap(predictor.letterPrior(prefix: "", previous: nil))
        let afterIch = try XCTUnwrap(predictor.letterPrior(prefix: "", previous: "ich"))
        // "ich habe", "ich bin" – h and b gain from the context.
        XCTAssertGreaterThan(afterIch.probability(of: "h") + afterIch.probability(of: "b"),
                             cold.probability(of: "h") + cold.probability(of: "b"))
    }

    func testPriorIsNilForUnknownPrefix() {
        XCTAssertNil(predictor.letterPrior(prefix: "xqzv", previous: nil))
    }

    func testPriorIsCaseInsensitiveAndHandlesSharpS() throws {
        let lower = try XCTUnwrap(predictor.letterPrior(prefix: "stra", previous: nil))
        let upper = try XCTUnwrap(predictor.letterPrior(prefix: "Stra", previous: nil))
        XCTAssertEqual(lower.probabilities, upper.probabilities)
        // "Straße": ß folds onto the s key.
        let strasse = try XCTUnwrap(predictor.letterPrior(prefix: "Stra", previous: nil))
        XCTAssertGreaterThan(strasse.probability(of: "s"), 0.05)
    }

    /// Computed on every keystroke on the main thread: must stay far below a frame.
    func testPriorIsFastForShortPrefixes() {
        let start = CFAbsoluteTimeGetCurrent()
        var n = 0
        for prefix in ["", "s", "e", "d", "ge", "sch", "a"] {
            for previous in [nil, "ich", "die"] where predictor.letterPrior(prefix: prefix, previous: previous) != nil { n += 1 }
        }
        let perCall = (CFAbsoluteTimeGetCurrent() - start) / Double(n) * 1000
        XCTAssertEqual(n, 21)
        XCTAssertLessThan(perCall, 10, "letterPrior took \(perCall) ms per call")
    }

    func testUserLexiconContributes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lp-\(UUID()).json")
        let user = UserLexicon(fileURL: url)
        user.learn(word: "Codextq", after: nil)
        user.learn(word: "Codextq", after: nil)
        let p = Predictor(lexicon: lex, user: user)
        let prior = try XCTUnwrap(p.letterPrior(prefix: "Codext", previous: nil))
        XCTAssertEqual(prior.mostLikely, "q")
    }

    // MARK: Hit testing

    private func frame(_ c: Character) -> KeyFrame {
        geometry.keyFrames.first { $0.key.character == c && $0.key.isLetter }!
    }

    /// A prior that makes `likely` almost certain.
    private func prior(favouring likely: Character) -> LetterPrior {
        var w = [Float](repeating: 0, count: KeyAlphabet.count)
        w[Int(KeyAlphabet.code(for: likely)!)] = 1
        return LetterPrior(weights: w)!
    }

    /// The touch offset moves points up; compensate so tests reason in visual coordinates.
    private func touch(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: p.y + geometry.rowHeight * KeyboardGeometry.HitTuning.touchOffsetY)
    }

    func testLikelyKeyStealsNeighbourEdge() {
        let o = frame("o"), p = frame("p")
        // Just inside p's cap, on the side facing o.
        let edgeOfP = touch(CGPoint(x: p.frame.minX + 1.5, y: p.frame.midY))
        XCTAssertEqual(geometry.keyFrame(at: edgeOfP)?.key.label, "p")
        XCTAssertEqual(geometry.keyFrame(at: edgeOfP, prior: nil)?.key.label, "p")
        XCTAssertEqual(geometry.keyFrame(at: edgeOfP, prior: prior(favouring: "o"))?.key.label, "o")
        // …but not when p itself is the likely key.
        XCTAssertEqual(geometry.keyFrame(at: edgeOfP, prior: prior(favouring: "p"))?.key.label, "p")
        // The gap between the two keys goes to the likely key in either direction.
        let gap = touch(CGPoint(x: (o.frame.maxX + p.frame.minX) / 2, y: p.frame.midY))
        XCTAssertEqual(geometry.keyFrame(at: gap, prior: prior(favouring: "o"))?.key.label, "o")
        XCTAssertEqual(geometry.keyFrame(at: gap, prior: prior(favouring: "p"))?.key.label, "p")
    }

    func testDeadCentreTapIsNeverStolen() {
        for kf in geometry.keyFrames where kf.key.isLetter {
            for likely in ["e", "n", "o", "a"] {
                let hit = geometry.keyFrame(at: touch(kf.center), prior: prior(favouring: Character(likely)))
                XCTAssertEqual(hit?.key.id, kf.key.id, "\(kf.key.label) centre stolen by \(likely)")
            }
        }
    }

    func testLikelyKeyReachesIntoRowBelowAndAbove() {
        let w = frame("w"), s = frame("s")
        // Top edge of s (below w/e) with w likely → w; bottom edge of w with s likely → s.
        let topOfS = touch(CGPoint(x: w.center.x, y: s.frame.minY + 0.5))
        XCTAssertEqual(geometry.keyFrame(at: topOfS, prior: nil)?.key.label, "s")
        XCTAssertEqual(geometry.keyFrame(at: topOfS, prior: prior(favouring: "w"))?.key.label, "w")
        let bottomOfW = touch(CGPoint(x: w.center.x, y: w.frame.maxY - 0.5))
        XCTAssertEqual(geometry.keyFrame(at: bottomOfW, prior: nil)?.key.label, "w")
        XCTAssertEqual(geometry.keyFrame(at: bottomOfW, prior: prior(favouring: "s"))?.key.label, "s")
    }

    func testWithoutPriorTheHitTestIsUnchanged() {
        for y in stride(from: 0, through: Int(geometry.size.height), by: 3) {
            for x in stride(from: 0, through: Int(geometry.size.width), by: 3) {
                let p = CGPoint(x: x, y: y)
                XCTAssertEqual(geometry.keyFrame(at: p, prior: nil)?.key.id, geometry.keyFrame(at: p)?.key.id)
            }
        }
    }

    /// With a real dictionary prior a likely key wins the gap but never the neighbour's inner cap.
    func testRealPriorTakesGapsButNotCapCentres() throws {
        let afterD = try XCTUnwrap(predictor.letterPrior(prefix: "d", previous: nil))
        XCTAssertEqual(afterD.mostLikely, "e")
        let w = frame("w"), e = frame("e")
        let gap = touch(CGPoint(x: (w.frame.maxX + e.frame.minX) / 2, y: w.frame.midY))
        XCTAssertEqual(geometry.keyFrame(at: gap, prior: afterD)?.key.label, "e")
        // Ordinary scatter: up to 60 % of the way from w's centre to its edge still hits w.
        for fraction in stride(from: 0.0, through: 0.6, by: 0.1) {
            let x = w.center.x + (w.frame.maxX - w.center.x) * fraction
            let hit = geometry.keyFrame(at: touch(CGPoint(x: x, y: w.frame.midY)), prior: afterD)
            XCTAssertEqual(hit?.key.label, "w", "stolen at \(fraction) of the half cap")
        }
        // Same vertically: the middle 60 % of s's cap belongs to s even though e/w are likelier.
        let s = frame("s")
        for fraction in stride(from: 0.0, through: 0.6, by: 0.1) {
            let y = s.center.y - (s.center.y - s.frame.minY) * fraction
            let hit = geometry.keyFrame(at: touch(CGPoint(x: s.center.x, y: y)), prior: afterD)
            XCTAssertEqual(hit?.key.label, "s", "stolen at \(fraction) of the half cap")
        }
    }

    func testFunctionKeysAreNotAffected() {
        let backspace = geometry.keyFrame(for: GermanLayouts.backspace)!
        let m = frame("m")
        let edgeOfBackspace = touch(CGPoint(x: backspace.frame.minX + 3, y: backspace.frame.midY))
        XCTAssertEqual(geometry.keyFrame(at: edgeOfBackspace, prior: prior(favouring: "m"))?.key.id, "backspace")
        let edgeOfM = touch(CGPoint(x: m.frame.maxX - 3, y: m.frame.midY))
        XCTAssertEqual(geometry.keyFrame(at: edgeOfM, prior: prior(favouring: "n"))?.key.label, "m",
                       "n is not adjacent to m's right edge; backspace cannot be stolen from")
        let space = geometry.keyFrame(for: GermanLayouts.space)!
        let topOfSpace = touch(CGPoint(x: frame("b").center.x, y: space.frame.minY + 3))
        XCTAssertEqual(geometry.keyFrame(at: topOfSpace, prior: prior(favouring: "b"))?.key.id, "space")
    }

    func testSymbolsLayerUsesPlainHitTest() {
        let symbols = KeyboardGeometry(layout: GermanLayouts.symbols(), size: CGSize(width: 390, height: 216))
        for kf in symbols.keyFrames {
            let hit = symbols.keyFrame(at: touch(kf.center), prior: prior(favouring: "e"))
            XCTAssertEqual(hit?.key.id, kf.key.id)
        }
    }
}
