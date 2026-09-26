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

    func testTimestampsAreAccepted() {
        let sim = GestureSimulator(keyMap: km)
        for (i, w) in ["hallo", "wahrscheinlich", "zusammen", "Geburtstag"].enumerated() {
            let g = sim.gesture(for: w, seed: UInt64(i + 1))
            let withTimes = decoder.decode(path: g.map(\.point), keyMap: km, timestamps: g.map(\.time), limit: 3)
            XCTAssertEqual(withTimes.first?.word.lowercased(), w.lowercased(), "\(withTimes.map(\.word))")
            // A timestamp list that doesn't match the path is ignored rather than trusted.
            let mismatched = decoder.decode(path: g.map(\.point), keyMap: km, timestamps: [0, 0.1], limit: 3)
            XCTAssertEqual(mismatched.map(\.word), decoder.decode(path: g.map(\.point), keyMap: km, limit: 3).map(\.word))
        }
    }

    func testSloppyEndsAreForgiven() {
        // Lifting a whole key width past the last letter still finds the word.
        for w in ["hallo", "danke", "morgen", "Zeit", "gut", "machen"] {
            let top = decodeTop(w, overshoot: km.keyWidth * 1.0)
            XCTAssertTrue(top.prefix(3).map { $0.lowercased() }.contains(w.lowercased()), "\(w): \(top)")
        }
    }

    func testTwoLetterWords() {
        for w in ["zu", "es", "in", "an", "ja", "du", "er", "so"] {
            XCTAssertEqual(decodeTop(w).first?.lowercased(), w, "\(decodeTop(w))")
        }
    }

    /// With the umlaut keys switched off, ä/ö/ü share the a/o/u keys. Words that start or end
    /// with an umlaut must still be reachable from those keys.
    func testUmlautWordsOnLayoutWithoutUmlautKeys() {
        let layout = GermanLayouts.letters(options: LayoutOptions(language: .german, germanUmlautKeys: false))
        let folded = KeyMap(geometry: KeyboardGeometry(layout: layout, size: CGSize(width: 390, height: 216)))!
        XCTAssertFalse(folded.foldedCodes.isEmpty)
        for w in ["über", "öfter", "ähnlich", "Übung"] {
            let path = TestSupport.syntheticPath(for: w, keyMap: folded)
            let top = decoder.decode(path: path, keyMap: folded, limit: 4).map(\.word)
            XCTAssertEqual(top.first?.lowercased(), w.lowercased(), "\(w): \(top)")
        }
    }

    func testLearnedWordsCanBeSwiped() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swipe-user-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let user = UserLexicon(fileURL: url)
        let words = ["Brudi", "Schatzi", "Codext"]
        for w in words {
            XCTAssertFalse(lex.containsIgnoringCase(w), "\(w) is in the dictionary; pick another test word")
            user.learn(word: w, after: nil)
            user.learn(word: w, after: nil)
        }
        let personal = SwipeDecoder(lexicon: lex, user: user)
        let sim = GestureSimulator(keyMap: km)
        for (i, w) in words.enumerated() {
            for v in 0..<3 {
                let g = sim.gesture(for: w, seed: UInt64(100 * i + v + 1))
                let top = personal.decode(path: g.map(\.point), keyMap: km, timestamps: g.map(\.time), limit: 3).map(\.word)
                XCTAssertTrue(top.contains(w), "\(w): \(top)")
            }
        }
        // Everyday words keep winning with the personal dictionary around.
        for w in ["hallo", "danke", "Schule", "schön"] {
            let top = personal.decode(path: TestSupport.syntheticPath(for: w), keyMap: km, limit: 3).map(\.word)
            XCTAssertEqual(top.first?.lowercased(), w.lowercased(), "\(top)")
        }
    }

    /// The keyboard decodes the partial path while the finger is still moving (live preview) on a
    /// background queue, while the main thread decodes finished gestures.
    func testPartialPathsAndConcurrentDecoding() {
        let sim = GestureSimulator(keyMap: km)
        let g = sim.gesture(for: "wahrscheinlich", seed: 7)
        var prefixes: [[CGPoint]] = []
        var next: TimeInterval = 0.06
        for (i, s) in g.enumerated() where s.time >= next {
            prefixes.append(g[...i].map(\.point))
            next += 0.06
        }
        prefixes.append(g.map(\.point))
        let sequential = prefixes.map { decoder.decode(path: $0, keyMap: km, limit: 3).map(\.word) }
        XCTAssertEqual(sequential.last?.first?.lowercased(), "wahrscheinlich", "\(sequential.last ?? [])")
        XCTAssertTrue(sequential.suffix(sequential.count / 2).allSatisfy { !$0.isEmpty })

        var concurrent = [[String]](repeating: [], count: prefixes.count)
        let lock = NSLock()
        let decoder = self.decoder, keyMap = km
        DispatchQueue.concurrentPerform(iterations: prefixes.count) { i in
            let words = decoder.decode(path: prefixes[i], keyMap: keyMap, limit: 3).map(\.word)
            lock.lock(); concurrent[i] = words; lock.unlock()
        }
        XCTAssertEqual(concurrent, sequential)
    }
}
