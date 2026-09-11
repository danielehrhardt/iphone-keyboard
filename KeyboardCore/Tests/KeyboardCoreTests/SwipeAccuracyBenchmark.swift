import XCTest
@testable import KeyboardCore

/// Larger-scale accuracy check with sloppier synthetic gestures: rounded corners, heavy jitter,
/// overshoot at the end and a slightly shifted start. Reports top-1 / top-3 rates.
final class SwipeAccuracyBenchmark: XCTestCase {
    let lex = TestSupport.lexicon
    lazy var decoder = SwipeDecoder(lexicon: lex)
    let km = TestSupport.keyMap

    static let words = """
    hallo danke bitte heute morgen gestern schön machen kommen gehen sehen sagen wissen denken glauben
    Freunde Arbeit Familie Kinder Eltern Mutter Vater Schule Stadt Straße Wasser Wetter Sonne Regen Winter
    wirklich eigentlich natürlich vielleicht wahrscheinlich zusammen später wieder immer niemals gerne
    Problem Frage Antwort Nachricht Termin Wochenende Urlaub Geburtstag Abend Mittag Woche Monat Jahr Zeit
    können müssen sollen wollen dürfen haben werden bleiben spielen lachen essen trinken schlafen fahren
    Auto Zug Flugzeug Fahrrad Wohnung Küche Garten Fenster Zimmer Tisch Stuhl Lampe Handy Computer Tastatur
    Deutschland Berlin München Hamburg Österreich Schweiz Europa Liebe Glück Angst Freude Hoffnung Ruhe
    schnell langsam groß klein warm kalt neu alt jung schwer leicht richtig falsch wichtig möglich einfach
    """.split(whereSeparator: \.isWhitespace).map(String.init)

    /// Rounded-corner path: bends are cut like a real thumb would, points get jitter.
    func realisticPath(for word: String, jitter: CGFloat, seed: UInt64) -> [CGPoint] {
        var rng = TestSupport.SplitMix(seed: seed)
        let codes = KeyAlphabet.swipeCodes(word)
        let centers = codes.map { km.centers[Int($0)] }
        guard centers.count >= 2 else { return centers }
        // Quadratic-bezier through corners with a corner cut of ~35% of the key width.
        var pts: [CGPoint] = []
        let startOffset = CGPoint(x: rng.jitter(km.keyWidth * 0.3), y: rng.jitter(km.keyHeight * 0.3))
        pts.append(CGPoint(x: centers[0].x + startOffset.x, y: centers[0].y + startOffset.y))
        for i in 1..<centers.count {
            let a = pts.last!, b = centers[i]
            let next = i + 1 < centers.count ? centers[i + 1] : nil
            let target: CGPoint
            if let next {
                // stop short of the corner and curve toward the next key
                let d = hypot(next.x - b.x, next.y - b.y)
                let cut = min(0.35 * km.keyWidth, d / 2)
                target = d > 0 ? CGPoint(x: b.x + (next.x - b.x) / d * cut, y: b.y + (next.y - b.y) / d * cut) : b
            } else {
                let d = hypot(b.x - a.x, b.y - a.y)
                let over = km.keyWidth * 0.4 * rng.unit()
                target = d > 0 ? CGPoint(x: b.x + (b.x - a.x) / d * over, y: b.y + (b.y - a.y) / d * over) : b
            }
            let steps = max(5, Int(hypot(target.x - a.x, target.y - a.y) / 5))
            for s in 1...steps {
                let t = CGFloat(s) / CGFloat(steps)
                // ease through the corner region
                let x = a.x + (b.x - a.x) * t * (2 - t) * 0.5 + (target.x - a.x) * t * t * 0.5
                let y = a.y + (b.y - a.y) * t * (2 - t) * 0.5 + (target.y - a.y) * t * t * 0.5
                pts.append(CGPoint(x: x + rng.jitter(jitter), y: y + rng.jitter(jitter)))
            }
        }
        return pts
    }

    func testRealisticGestureAccuracy() {
        var top1 = 0, top3 = 0, total = 0
        var misses: [String] = []
        for w in Self.words {
            for seed in 1...4 {
                total += 1
                let path = realisticPath(for: w, jitter: km.keyWidth * 0.25, seed: UInt64(seed) * 7919)
                let out = decoder.decode(path: path, keyMap: km, limit: 4).map { $0.word.lowercased() }
                if out.first == w.lowercased() { top1 += 1; top3 += 1 }
                else if out.prefix(3).contains(w.lowercased()) { top3 += 1; misses.append("\(w)→\(out.first ?? "-")") }
                else { misses.append("\(w)→\(out.prefix(3).joined(separator: "/"))") }
            }
        }
        let r1 = Double(top1) / Double(total), r3 = Double(top3) / Double(total)
        print("SWIPE ACCURACY top1=\(String(format: "%.3f", r1)) top3=\(String(format: "%.3f", r3)) n=\(total)")
        print("MISSES: \(misses.prefix(40).joined(separator: ", "))")
        XCTAssertGreaterThan(r1, 0.80, "top-1 \(r1)")
        XCTAssertGreaterThan(r3, 0.93, "top-3 \(r3)")
    }
}
