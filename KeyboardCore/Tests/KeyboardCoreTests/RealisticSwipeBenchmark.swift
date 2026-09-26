import XCTest
import CoreGraphics
@testable import KeyboardCore

/// Accuracy and speed of the swipe decoder on human-like gestures (`GestureSimulator`): variable
/// speed and touch sample rate, corner cutting, sloppy starts and ends, gliding over letters on
/// the way, wobble and jitter, at the reference iPhone key pitch.
///
/// Word sets, all seeded and deterministic:
/// - TEST: 300 distinct words drawn in proportion to their frequency (many short function words,
///   a long tail of content words), three gestures each. The thresholds are checked here.
/// - TRAIN: 300 other words drawn the same way. Parameters are tuned on this split only, so a
///   change that merely memorises words shows up as a gap between the two.
/// - HAND: the hand-picked lists below (short and long words, umlauts, nouns).
/// - TOKENS: 400 draws *with* replacement, i.e. running text as a user types it (common words
///   repeat), one gesture each.
/// - SLOPPY: the TEST words once more, swiped 1.6 times as imprecisely as the others: nothing is
///   tuned for this, it shows how gracefully accuracy degrades.
///
/// No previous word is given, so only the unigram prior helps; words that share their key
/// sequence ("den"/"denn", "wissen"/"weißen") or glide over the same keys ("war"/"Wasser") are
/// decided by frequency alone and cap what any decoder can reach here.
///
/// Recorded on an Apple Silicon Mac, release build (top-1 / top-3; mean / max time per decode).
/// "Before" is the decoder as it was when this benchmark was written.
///
///                            before                            after
///     de/QWERTZ  TEST     0.892 / 0.979   1.0 / 4.1 ms      0.963 / 0.999   0.3 / 4.6 ms
///                TOKENS   0.938 / 0.993                     0.963 / 1.000
///                SLOPPY   0.757 / 0.923                     0.880 / 0.973
///                HAND     0.947 / 0.996                     0.971 / 1.000
///                TRAIN    0.850 / 0.974                     0.951 / 0.999
///     en/QWERTY  TEST     0.918 / 0.989   1.1 / 9.2 ms      0.969 / 1.000   0.3 / 2.6 ms
///                TOKENS   0.938 / 0.990                     0.968 / 0.998
///                SLOPPY   0.793 / 0.923                     0.883 / 0.977
///                HAND     0.978 / 1.000                     0.989 / 1.000
///                TRAIN    0.903 / 0.986                     0.957 / 1.000
final class RealisticSwipeBenchmark: XCTestCase {

    static let germanHandWords = SwipeAccuracyBenchmark.words + """
    zu es in an ja du er wir ich und die der das ist mit auf den von sie wie was bei nur gut so am im um da wo ab
    Geburtstag wahrscheinlich Entschuldigung Verabredung Hausaufgaben Nachrichten
    """.split(whereSeparator: \.isWhitespace).map(String.init)

    static let englishHandWords = """
    the and you it is in on at to of we me my he be do go so no up if or as an by
    hello thanks world would could should about their there where which little really please morning tomorrow
    yesterday together different important keyboard computer birthday weekend family friend phone message meeting
    coffee dinner lunch time work home good great love know think going want need like just what when have been
    with this that from they will your something because people everything anything beautiful probably actually
    """.split(whereSeparator: \.isWhitespace).map(String.init)

    struct Case {
        let language: KeyboardLanguage
        let lexicon: Lexicon
        let keyMap: KeyMap
        let handWords: [String]
        var tag: String { language == .german ? "de/QWERTZ" : "en/QWERTY" }
    }

    static let german = Case(language: .german, lexicon: TestSupport.lexicon, keyMap: KeyMap.reference(language: .german),
                             handWords: germanHandWords)
    static let english = Case(language: .english, lexicon: TestSupport.englishLexicon, keyMap: KeyMap.reference(language: .english),
                              handWords: englishHandWords)

    struct Result: CustomStringConvertible {
        var top1 = 0, top3 = 0, total = 0
        var totalNanos: UInt64 = 0, maxNanos: UInt64 = 0
        var byLength: [String: (hit: Int, total: Int)] = [:]
        var misses: [String] = []

        var rate1: Double { Double(top1) / Double(max(total, 1)) }
        var rate3: Double { Double(top3) / Double(max(total, 1)) }
        var meanMillis: Double { Double(totalNanos) / Double(max(total, 1)) / 1e6 }
        var maxMillis: Double { Double(maxNanos) / 1e6 }

        var description: String {
            let lengths = ["2-3", "4-6", "7+"].map { k -> String in
                let v = byLength[k] ?? (0, 0)
                return "\(k):\(String(format: "%.3f", Double(v.hit) / Double(max(v.total, 1))))"
            }.joined(separator: " ")
            return String(format: "top1=%.3f top3=%.3f n=%d mean=%.2fms max=%.2fms", rate1, rate3, total, meanMillis, maxMillis)
                + " [top1 by length \(lengths)]"
        }
    }

    // MARK: Word sets

    /// Words a swipe can produce: two or more keys (one key is a tap), letters and apostrophes.
    static func isSwipeable(_ w: String) -> Bool {
        w.count >= 2 && w.allSatisfy { $0.isLetter || $0 == "'" } && KeyAlphabet.swipeCodes(w).count >= 2
    }

    /// `count` distinct words (by lowercase spelling), drawn without replacement with probability
    /// proportional to their frequency (Efraimidis–Spirakis keys).
    static func sampleWords(_ lexicon: Lexicon, count: Int, seed: UInt64, excluding: Set<String> = []) -> [String] {
        var rng = TestSupport.SplitMix(seed: seed)
        var keyed: [(key: Double, word: String)] = []
        keyed.reserveCapacity(lexicon.count)
        for id in 0..<lexicon.count {
            let w = lexicon.words[id]
            guard isSwipeable(w) else { continue }
            let u = max(Double(rng.next() % 1_000_000_007) / 1_000_000_007, 1e-12)
            keyed.append((log(-log(u)) - Double(lexicon.logProb[id]), w))
        }
        keyed.sort { $0.key < $1.key }
        var seen = excluding
        var out: [String] = []
        for k in keyed where out.count < count {
            if seen.insert(k.word.lowercased()).inserted { out.append(k.word) }
        }
        return out
    }

    /// `count` words drawn with replacement in proportion to frequency: running text.
    static func sampleTokens(_ lexicon: Lexicon, count: Int, seed: UInt64) -> [String] {
        var ids: [Int] = []
        var cumulative: [Double] = []
        var total = 0.0
        for id in 0..<lexicon.count where isSwipeable(lexicon.words[id]) {
            total += exp(Double(lexicon.logProb[id]))
            ids.append(id)
            cumulative.append(total)
        }
        var rng = TestSupport.SplitMix(seed: seed)
        return (0..<count).map { _ in
            let u = Double(rng.next() % 1_000_000_007) / 1_000_000_007 * total
            var lo = 0, hi = cumulative.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if cumulative[mid] < u { lo = mid + 1 } else { hi = mid }
            }
            return lexicon.words[ids[lo]]
        }
    }

    static func testWords(_ c: Case) -> [String] { sampleWords(c.lexicon, count: 300, seed: 0x7E57) }

    static func trainWords(_ c: Case) -> [String] {
        let test = Set((testWords(c) + c.handWords).map { $0.lowercased() })
        return sampleWords(c.lexicon, count: 300, seed: 0x7EA1, excluding: test)
    }

    static func tokenWords(_ c: Case) -> [String] { sampleTokens(c.lexicon, count: 400, seed: 0x70CE5) }

    // MARK: Running

    static func run(_ decoder: SwipeDecoder, _ c: Case, words: [String], variants: Int = 3, seed: UInt64 = 1,
                    sloppiness: CGFloat = 1) -> Result {
        run(c, words: words, variants: variants, seed: seed, sloppiness: sloppiness) {
            decoder.decode(path: $0, keyMap: c.keyMap, timestamps: $1, limit: 4)
        }
    }

    /// Decodes `variants` gestures per word; a hit is the word (case-insensitive) at rank 1 / 1–3.
    /// `decode` gets the path and the touch timestamps.
    static func run(_ c: Case, words: [String], variants: Int = 3, seed: UInt64 = 1, sloppiness: CGFloat = 1,
                    decode: ([CGPoint], [TimeInterval]) -> [SwipeCandidate]) -> Result {
        var sim = GestureSimulator(keyMap: c.keyMap)
        sim.sloppiness = sloppiness
        var r = Result()
        for (wi, w) in words.enumerated() {
            let target = w.lowercased()
            for v in 0..<variants {
                let g = sim.gesture(for: w, seed: seed &* 1_000_003 &+ UInt64(wi) &* 7919 &+ UInt64(v) &* 104_729)
                let path = g.map(\.point), times = g.map(\.time)
                let t0 = DispatchTime.now().uptimeNanoseconds
                let out = decode(path, times).map { $0.word.lowercased() }
                let dt = DispatchTime.now().uptimeNanoseconds - t0
                r.totalNanos += dt
                r.maxNanos = max(r.maxNanos, dt)
                r.total += 1
                let len = KeyAlphabet.codes(w).count
                let bucket = len <= 3 ? "2-3" : (len <= 6 ? "4-6" : "7+")
                var entry = r.byLength[bucket] ?? (0, 0)
                entry.total += 1
                if out.first == target {
                    r.top1 += 1; r.top3 += 1; entry.hit += 1
                } else {
                    if out.prefix(3).contains(target) { r.top3 += 1 }
                    r.misses.append("\(w)→\(out.prefix(3).joined(separator: "/"))")
                }
                r.byLength[bucket] = entry
            }
        }
        return r
    }

    // MARK: Tests

    struct Report { let test, hand, tokens, sloppy: Result }

    func report(_ c: Case) -> Report {
        let decoder = SwipeDecoder(lexicon: c.lexicon)
        _ = Self.run(decoder, c, words: Array(c.handWords.prefix(5)), variants: 1)      // warm-up
        let test = Self.run(decoder, c, words: Self.testWords(c))
        let r = Report(test: test,
                       hand: Self.run(decoder, c, words: c.handWords, seed: 2),
                       tokens: Self.run(decoder, c, words: Self.tokenWords(c), variants: 1, seed: 3),
                       sloppy: Self.run(decoder, c, words: Self.testWords(c), variants: 1, seed: 4, sloppiness: 1.6))
        print("REALISTIC SWIPE \(c.tag) TEST   \(r.test)")
        print("REALISTIC SWIPE \(c.tag) HAND   \(r.hand)")
        print("REALISTIC SWIPE \(c.tag) TOKENS \(r.tokens)")
        print("REALISTIC SWIPE \(c.tag) SLOPPY \(r.sloppy)")
        print("REALISTIC SWIPE \(c.tag) TEST MISSES: \(test.misses.prefix(60).joined(separator: ", "))")
        return r
    }

    func check(_ r: Report, test: (Double, Double), tokens: (Double, Double), sloppy: (Double, Double)) {
        XCTAssertGreaterThan(r.test.rate1, test.0, "TEST top-1")
        XCTAssertGreaterThan(r.test.rate3, test.1, "TEST top-3")
        XCTAssertGreaterThan(r.tokens.rate1, tokens.0, "TOKENS top-1")
        XCTAssertGreaterThan(r.tokens.rate3, tokens.1, "TOKENS top-3")
        XCTAssertGreaterThan(r.sloppy.rate1, sloppy.0, "SLOPPY top-1")
        XCTAssertGreaterThan(r.sloppy.rate3, sloppy.1, "SLOPPY top-3")
        XCTAssertGreaterThan(r.hand.rate1, 0.95, "HAND top-1")
        // Generous so a busy machine doesn't fail the build; typical numbers are in the header.
        XCTAssertLessThan(r.test.meanMillis, 3, "mean decode time")
        XCTAssertLessThan(r.test.maxMillis, 25, "slowest decode")
    }

    // Thresholds sit a little below the recorded numbers (see the header): they catch
    // regressions without failing on the odd gesture that flips with an unrelated change.

    func testGermanQWERTZ() {
        check(report(Self.german), test: (0.94, 0.99), tokens: (0.94, 0.99), sloppy: (0.85, 0.95))
    }

    func testEnglishQWERTY() {
        check(report(Self.english), test: (0.945, 0.99), tokens: (0.945, 0.99), sloppy: (0.85, 0.95))
    }

    /// Training split, for comparing parameter changes (thresholds live on TEST only).
    func testTrainSplit() {
        for c in [Self.german, Self.english] {
            let r = Self.run(SwipeDecoder(lexicon: c.lexicon), c, words: Self.trainWords(c))
            print("REALISTIC SWIPE \(c.tag) TRAIN  \(r)")
        }
    }
}
