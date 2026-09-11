import Foundation
import CoreGraphics
@testable import KeyboardCore

enum TestSupport {
    static let lexicon: Lexicon = {
        do { return try Lexicon.loadBundled() } catch { fatalError("lexicon: \(error)") }
    }()

    static let keyMap = KeyMap.reference()

    /// Synthesises a finger path for a word: straight segments between key centres with a
    /// little jitter and extra samples so it resembles a real gesture.
    static func syntheticPath(for word: String, keyMap: KeyMap = keyMap, jitter: CGFloat = 0, seed: UInt64 = 1, overshootEnd: CGFloat = 0) -> [CGPoint] {
        var rng = SplitMix(seed: seed)
        let codes = KeyAlphabet.swipeCodes(word)
        var centers = codes.map { keyMap.centers[Int($0)] }
        if overshootEnd > 0, centers.count >= 2 {
            let a = centers[centers.count - 2], b = centers[centers.count - 1]
            let d = hypot(b.x - a.x, b.y - a.y)
            if d > 0 { centers[centers.count - 1] = CGPoint(x: b.x + (b.x - a.x) / d * overshootEnd, y: b.y + (b.y - a.y) / d * overshootEnd) }
        }
        guard centers.count >= 2 else { return centers }
        var pts: [CGPoint] = []
        for i in 1..<centers.count {
            let a = centers[i - 1], b = centers[i]
            let steps = max(4, Int(hypot(b.x - a.x, b.y - a.y) / 6))
            for s in 0..<steps {
                let t = CGFloat(s) / CGFloat(steps)
                pts.append(CGPoint(x: a.x + (b.x - a.x) * t + rng.jitter(jitter), y: a.y + (b.y - a.y) * t + rng.jitter(jitter)))
            }
        }
        pts.append(centers[centers.count - 1])
        return pts
    }

    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> CGFloat { CGFloat(next() % 10_000) / 10_000 }
        mutating func jitter(_ amount: CGFloat) -> CGFloat { amount == 0 ? 0 : (unit() * 2 - 1) * amount }
    }
}
