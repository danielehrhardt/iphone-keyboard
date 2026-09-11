import XCTest
@testable import KeyboardCore

final class TapMapTests: XCTestCase {
    let keyMap = KeyMap.reference()
    let geometry = KeyboardGeometry(layout: GermanLayouts.letters(), size: CGSize(width: 390, height: 216))

    private func code(_ c: Character) -> UInt8 { KeyAlphabet.code(for: c)! }
    private func center(_ c: Character) -> CGPoint { keyMap.centers[Int(code(c))] }
    private func frame(_ label: String) -> KeyFrame { geometry.keyFrames.first { $0.key.label == label }! }

    /// Taps `dx`/`dy` pitches off the centre of every letter of `word`.
    private func taps(_ word: String, dx: CGFloat, dy: CGFloat) -> [CGPoint] {
        word.map { ch in
            guard let code = KeyAlphabet.code(for: ch) else { return .zero }   // non-letters have no key
            let c = keyMap.centers[Int(code)]
            return CGPoint(x: c.x + dx * keyMap.pitchX, y: c.y + dy * keyMap.pitchY)
        }
    }

    // MARK: Learning

    func testEmptyMapIsNeutral() {
        let map = TapMap(fileURL: nil)
        XCTAssertEqual(map.offsets(for: keyMap), .neutral)
        XCTAssertEqual(map.totalSamples, 0)
        XCTAssertNil(map.layer(for: keyMap))
        let n = TapMap.Offsets.neutral
        XCTAssertEqual(n.dx[Int(code("a"))], 0)
        XCTAssertEqual(n.dy[Int(code("a"))], CGFloat(TapMap.Tuning.defaultDy), accuracy: 1e-6)
    }

    func testOffsetsFollowSamplesAndTheDefaultFadesOut() {
        let map = TapMap(fileURL: nil)
        let e = code("e")
        map.learn([TapMap.Sample(code: e, dx: 0.2, dy: -0.1)], keyMap: keyMap)
        var o = map.offsets(for: keyMap)
        // One tap against `pseudoCount` pseudo-taps of default: a small step towards the sample.
        let n = 1 + TapMap.Tuning.pseudoCount
        XCTAssertEqual(o.dx[Int(e)], CGFloat(0.2 / n), accuracy: 1e-5)
        XCTAssertEqual(o.dy[Int(e)], CGFloat((-0.1 + TapMap.Tuning.defaultDy * TapMap.Tuning.pseudoCount) / n), accuracy: 1e-5)
        // Every other key is untouched.
        XCTAssertEqual(o.dx[Int(code("r"))], 0)

        for _ in 0..<200 { map.learn([TapMap.Sample(code: e, dx: 0.2, dy: -0.1)], keyMap: keyMap) }
        o = map.offsets(for: keyMap)
        XCTAssertEqual(o.dx[Int(e)], 0.2, accuracy: 0.015)
        XCTAssertEqual(o.dy[Int(e)], -0.1, accuracy: 0.015)
        XCTAssertEqual(map.totalSamples, 201)
        XCTAssertEqual(map.layer(for: keyMap)?.learnedKeyCount, 1)
    }

    func testShiftIsClamped() {
        let map = TapMap(fileURL: nil)
        for _ in 0..<300 { map.learn([TapMap.Sample(code: code("q"), dx: 0.5, dy: 0.5)], keyMap: keyMap) }
        let o = map.offsets(for: keyMap)
        XCTAssertEqual(o.dx[Int(code("q"))], CGFloat(TapMap.Tuning.maxShift))
        XCTAssertEqual(o.dy[Int(code("q"))], CGFloat(TapMap.Tuning.maxShift))
    }

    func testUndoRestoresTheStateBeforeTheLastBatch() {
        let map = TapMap(fileURL: nil)
        map.learn([TapMap.Sample(code: code("a"), dx: 0.1, dy: 0)], keyMap: keyMap)
        let before = map.layer(for: keyMap)!
        // A batch touching one key twice must be undone as a whole.
        map.learn([TapMap.Sample(code: code("a"), dx: 0.3, dy: 0), TapMap.Sample(code: code("a"), dx: 0.3, dy: 0),
                   TapMap.Sample(code: code("l"), dx: -0.2, dy: 0)], keyMap: keyMap)
        XCTAssertNotEqual(map.layer(for: keyMap), before)
        map.undoLastLearning()
        XCTAssertEqual(map.layer(for: keyMap), before)
        XCTAssertEqual(map.totalSamples, 1)
        // Only one step back: a second undo is a no-op.
        map.undoLastLearning()
        XCTAssertEqual(map.layer(for: keyMap), before)
    }

    func testLayersAreKeptPerKeyboardWidth() {
        let map = TapMap(fileURL: nil)
        let landscape = KeyMap.reference(width: 844, height: 160)
        map.learn([TapMap.Sample(code: code("a"), dx: 0.2, dy: 0)], keyMap: keyMap)
        map.learn([TapMap.Sample(code: code("a"), dx: -0.2, dy: 0)], keyMap: landscape)
        XCTAssertGreaterThan(map.offsets(for: keyMap).dx[Int(code("a"))], 0)
        XCTAssertLessThan(map.offsets(for: landscape).dx[Int(code("a"))], 0)
        XCTAssertEqual(map.layers.map(\.pitchX), [keyMap.pitchX.rounded(), landscape.pitchX.rounded()])
        XCTAssertEqual(map.layers.first?.arrangement, "qwertzuiopüasdfghjklöäyxcvbnm")

        // Same width, letters arranged differently (QWERTY: y and z swapped): its own layer.
        var centers = keyMap.centers
        centers.swapAt(Int(code("y")), Int(code("z")))
        let qwerty = KeyMap(centers: centers, keyWidth: keyMap.keyWidth, keyHeight: keyMap.keyHeight, pitchX: keyMap.pitchX, pitchY: keyMap.pitchY)
        XCTAssertEqual(TapMap.arrangement(of: qwerty), "qwertyuiopüasdfghjklöäzxcvbnm")
        XCTAssertNil(map.layer(for: qwerty))
        map.learn([TapMap.Sample(code: code("a"), dx: -0.2, dy: 0)], keyMap: qwerty)
        XCTAssertGreaterThan(map.offsets(for: keyMap).dx[Int(code("a"))], 0)
        XCTAssertEqual(map.layers.count, 3)
    }

    // MARK: Attribution

    func testCommittedWordConfirmsEveryTap() {
        let samples = TapMap.samples(taps: taps("hallo", dx: 0.1, dy: -0.05), typed: "hallo", committed: "hallo", keyMap: keyMap)
        XCTAssertEqual(samples.map(\.code), KeyAlphabet.codes("hallo"))
        for s in samples {
            XCTAssertEqual(s.dx, 0.1, accuracy: 1e-4)
            XCTAssertEqual(s.dy, -0.05, accuracy: 1e-4)
        }
    }

    func testCorrectionAttributesTheTapToTheKeyTheUserMeant() {
        // Typed "hakko", corrected to "hallo": the two k taps landed near the k/l boundary and were
        // meant for l, so relative to l they count as taps half a key to the left.
        var points = taps("hakko", dx: 0, dy: 0)
        for i in [2, 3] { points[i].x = center("k").x + 0.48 * keyMap.pitchX }
        let samples = TapMap.samples(taps: points, typed: "hakko", committed: "hallo", keyMap: keyMap)
        XCTAssertEqual(samples.map(\.code), KeyAlphabet.codes("hallo"))
        let expected = Float((points[2].x - center("l").x) / keyMap.pitchX)
        XCTAssertLessThan(expected, -0.4)
        XCTAssertEqual(samples[2].dx, expected, accuracy: 1e-4)
        XCTAssertEqual(samples[3].dx, expected, accuracy: 1e-4)
        XCTAssertEqual(samples[0].dx, 0, accuracy: 1e-4)
        // A dead-centre tap on k that gets "corrected" to l is a spelling fix, not a slip.
        let centred = TapMap.samples(taps: taps("hakko", dx: 0, dy: 0), typed: "hakko", committed: "hallo", keyMap: keyMap)
        XCTAssertEqual(centred.map(\.code), KeyAlphabet.codes("hao"))
    }

    func testFarCorrectionsAndSlipsAreNotLearned() {
        // "q" → "p" is a spelling fix across the keyboard, not a slip: skipped, the rest is kept.
        var samples = TapMap.samples(taps: taps("qas", dx: 0, dy: 0), typed: "qas", committed: "pas", keyMap: keyMap)
        XCTAssertEqual(samples.map(\.code), KeyAlphabet.codes("as"))
        // A tap more than half a key off its target is a slip.
        samples = TapMap.samples(taps: taps("ab", dx: 0.7, dy: 0), typed: "ab", committed: "ab", keyMap: keyMap)
        XCTAssertTrue(samples.isEmpty)
        // Length changes ("das" → "dass") cannot be aligned and yield nothing.
        samples = TapMap.samples(taps: taps("das", dx: 0, dy: 0), typed: "das", committed: "dass", keyMap: keyMap)
        XCTAssertTrue(samples.isEmpty)
        // Case and non-letters are tolerated.
        samples = TapMap.samples(taps: taps("Ha-l", dx: 0, dy: 0), typed: "Ha-l", committed: "ha-l", keyMap: keyMap)
        XCTAssertEqual(samples.map(\.code), KeyAlphabet.codes("hal"))
    }

    // MARK: Hit test

    func testNeutralOffsetsMatchThePriorHitTestOnEveryCapCentre() {
        for kf in geometry.keyFrames {
            // The prior hit test nudges the touch up; the neutral map shifts every centre down by the
            // same amount, so the two agree wherever there is no prior.
            let hit = geometry.keyFrame(at: kf.center, prior: nil, offsets: .neutral)
            XCTAssertEqual(hit?.key.id, kf.key.id, "centre of \(kf.key.id)")
        }
    }

    func testWithoutOffsetsThePriorHitTestIsUsed() {
        for kf in geometry.keyFrames {
            for p in [kf.center, CGPoint(x: kf.frame.minX + 1, y: kf.frame.maxY - 1)] {
                XCTAssertEqual(geometry.keyFrame(at: p, prior: nil, offsets: nil)?.key.id, geometry.keyFrame(at: p, prior: nil)?.key.id)
            }
        }
    }

    func testLearnedShiftMovesTheBoundaryBetweenNeighbours() {
        // This user taps every key a fifth of a key to the right of centre.
        let map = TapMap(fileURL: nil)
        for _ in 0..<60 {
            map.learn(KeyAlphabet.letters.map { TapMap.Sample(code: code($0), dx: 0.2, dy: 0) }, keyMap: keyMap)
        }
        let offsets = map.offsets(for: keyMap)
        let k = frame("k"), l = frame("l")
        // A touch just inside l's cap edge is, for this user, an attempt at k.
        let touch = CGPoint(x: l.frame.minX + 2, y: k.center.y)
        XCTAssertEqual(geometry.keyFrame(at: touch)?.key.label, "l")
        XCTAssertEqual(geometry.keyFrame(at: touch, prior: nil, offsets: .neutral)?.key.label, "l")
        XCTAssertEqual(geometry.keyFrame(at: touch, prior: nil, offsets: offsets)?.key.label, "k")
        // Dead-centre taps still hit what they show.
        for kf in geometry.keyFrames where kf.key.isLetter {
            XCTAssertEqual(geometry.keyFrame(at: kf.center, prior: nil, offsets: offsets)?.key.id, kf.key.id)
        }
    }

    func testFunctionKeysKeepTheirHitBox() {
        var dx = [CGFloat](repeating: 0, count: KeyAlphabet.count), dy = dx
        // Extreme map: every letter shifted a quarter key down and to the left.
        for i in dx.indices { dx[i] = -0.25; dy[i] = 0.25 }
        let offsets = TapMap.Offsets(dx: dx, dy: dy)
        let space = geometry.keyFrames.first { $0.key.id == "space" }!
        let shift = geometry.keyFrames.first { $0.key.action == .shift }!
        let b = frame("b"), y = frame("y")
        let topOfSpace = CGPoint(x: b.center.x, y: space.frame.minY + 2)
        XCTAssertEqual(geometry.keyFrame(at: topOfSpace, prior: nil, offsets: offsets)?.key.id, "space")
        let edgeOfShift = CGPoint(x: shift.frame.maxX - 2, y: y.center.y)
        XCTAssertEqual(geometry.keyFrame(at: edgeOfShift, prior: nil, offsets: offsets)?.key.action, .shift)
        // Symbols layer: plain hit test.
        let symbols = KeyboardGeometry(layout: GermanLayouts.layout(for: .symbols, options: LayoutOptions()), size: geometry.size)
        for kf in symbols.keyFrames {
            XCTAssertEqual(symbols.keyFrame(at: kf.center, prior: nil, offsets: offsets)?.key.id, kf.key.id)
        }
    }

    // MARK: Persistence

    func testRoundTripsThroughTheFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tap-map-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let map = TapMap(fileURL: url)
        map.learn([TapMap.Sample(code: code("s"), dx: 0.1, dy: 0.2)], keyMap: keyMap)
        map.saveNow()
        let reloaded = TapMap(fileURL: url)
        XCTAssertEqual(reloaded.layer(for: keyMap), map.layer(for: keyMap))
        XCTAssertEqual(reloaded.totalSamples, 1)

        // The other process reset the map; reloadIfChanged picks it up.
        reloaded.removeAll()
        reloaded.saveNow()
        XCTAssertEqual(map.totalSamples, 1)
        map.reloadIfChanged()
        XCTAssertEqual(map.totalSamples, 0)
    }
}
