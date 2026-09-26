import Foundation
import CoreGraphics
@testable import KeyboardCore

/// Synthesises human-like swipe gestures, sampled like the touch stream an iPhone delivers.
///
/// Straight lines through key centres (see `TestSupport.syntheticPath`) flatter a decoder: real
/// fingers aim at a *via point* somewhere on the key, cut corners, overshoot or stop short at
/// the end, glide over letters that lie on the way without bending, and move fast on straight
/// runs but slowly through turns. The touch panel samples at a fixed rate, so a gesture has few,
/// widely spaced points on straight runs and dense clusters where the finger slows down. Each
/// gesture draws its own "style" (precision, speed, corner cutting, sample rate) from a seeded
/// generator, so results are reproducible.
struct GestureSimulator {

    struct Sample {
        var point: CGPoint
        var time: TimeInterval
    }

    /// How one gesture is performed. All lengths are in key widths unless noted.
    struct Style {
        /// Scatter of the aimed-at point around a key centre (standard deviation).
        var viaSigma: CGFloat
        /// A consistent offset of the whole gesture (thumbs tend to land low), in key widths/heights.
        var offsetX: CGFloat
        var offsetY: CGFloat
        /// How far a turn is cut towards its inside; negative values overshoot the key.
        var cornerCut: CGFloat
        /// Radius over which corners are rounded.
        var filletRadius: CGFloat
        /// Peak finger speed on straight runs, points per second.
        var peakSpeed: CGFloat
        /// Fraction of the speed lost in a sharp turn.
        var turnSlowdown: CGFloat
        /// Touch sample rate (Hz): 60 for plain touches, 120 with coalesced touches on ProMotion.
        var sampleRate: Double
        /// Digitiser noise per sample, points.
        var jitter: CGFloat
        /// Offset of the touch-down point from the first key centre.
        var startOffset: CGFloat
        /// Where the finger lifts relative to the last key, along the incoming direction
        /// (positive = overshoot) and across it.
        var endAlong: CGFloat
        var endAcross: CGFloat
        /// A lateral bump somewhere along the path (0 = none).
        var wobble: CGFloat
        /// Dwell time on double letters ("ll" in "hallo"), seconds.
        var doubleLetterDwell: Double
        /// The finger rests a moment after touch-down and before lift-off, seconds.
        var startDwell: Double
        var endDwell: Double
        /// A small curl when the finger lifts off, points.
        var liftHook: CGFloat

        static func random(_ rng: inout TestSupport.SplitMix) -> Style {
            Style(viaSigma: 0.1 + 0.2 * rng.unit(),
                  offsetX: rng.jitter(0.12),
                  offsetY: 0.05 + rng.jitter(0.12),
                  cornerCut: -0.1 + 0.35 * rng.unit(),
                  filletRadius: 0.25 + 0.45 * rng.unit(),
                  peakSpeed: 450 + 750 * rng.unit(),
                  turnSlowdown: 0.35 + 0.4 * rng.unit(),
                  sampleRate: rng.unit() < 0.5 ? 60 : 120,
                  jitter: 0.3 + 1.0 * rng.unit(),
                  startOffset: 0.4 * rng.unit().squareRoot(),
                  endAlong: -0.35 + 0.85 * rng.unit(),
                  endAcross: rng.jitter(0.2),
                  wobble: rng.unit() < 0.25 ? 0.1 + 0.2 * rng.unit() : 0,
                  doubleLetterDwell: rng.unit() < 0.3 ? 0.04 + 0.1 * Double(rng.unit()) : 0,
                  startDwell: 0.08 * Double(rng.unit()),
                  endDwell: 0.06 * Double(rng.unit()),
                  liftHook: rng.unit() < 0.3 ? 3 + 6 * rng.unit() : 0)
        }
    }

    let keyMap: KeyMap
    /// Scales the imprecision of every style (aim, start/end offsets, corner cutting, wobble):
    /// 1 is the benchmark's normal user, 1.6 a hurried one-handed swipe.
    var sloppiness: CGFloat = 1

    /// A gesture for `word` with a style drawn from `seed`.
    func gesture(for word: String, seed: UInt64) -> [Sample] {
        var rng = TestSupport.SplitMix(seed: seed)
        var style = Style.random(&rng)
        if sloppiness != 1 {
            style.viaSigma *= sloppiness
            style.offsetX *= sloppiness; style.offsetY *= sloppiness
            style.cornerCut *= sloppiness; style.filletRadius *= sloppiness
            style.startOffset *= sloppiness
            style.endAlong *= sloppiness; style.endAcross *= sloppiness
            style.wobble *= sloppiness
        }
        return gesture(for: word, style: style, rng: &rng)
    }

    func gesture(for word: String, style: Style, rng: inout TestSupport.SplitMix) -> [Sample] {
        let kw = keyMap.keyWidth, kh = keyMap.keyHeight
        // Keys the finger passes, with a flag for letters typed twice in a row (a dwell spot).
        var keys: [(center: CGPoint, doubled: Bool)] = []
        var lastCode: UInt8?
        for ch in word {
            guard let code = KeyAlphabet.code(for: ch) else { continue }
            if code == lastCode { keys[keys.count - 1].doubled = true; continue }
            keys.append((keyMap.centers[Int(code)], false))
            lastCode = code
        }
        guard keys.count >= 2 else { return keys.map { Sample(point: $0.center, time: 0) } }
        let n = keys.count

        // 1. Via points: scattered around the key centres.
        let offset = CGPoint(x: style.offsetX * kw, y: style.offsetY * kh)
        var via = keys.map { k in
            CGPoint(x: k.center.x + offset.x + gaussian(&rng) * style.viaSigma * kw,
                    y: k.center.y + offset.y + gaussian(&rng) * style.viaSigma * kh * 0.8)
        }
        // Touch-down: anywhere within `startOffset` of the first key.
        let angle = rng.unit() * 2 * .pi
        via[0] = CGPoint(x: keys[0].center.x + cos(angle) * style.startOffset * kw,
                         y: keys[0].center.y + sin(angle) * style.startOffset * kw)

        // 2. Interior letters: cut sharp turns, glide straight over letters that are on the way.
        var turn = [CGFloat](repeating: 0, count: n)
        for i in 1..<(n - 1) {
            let a = keys[i - 1].center, b = keys[i].center, c = keys[i + 1].center
            let u1 = unit(a - b), u2 = unit(c - b)
            let bisector = u1 + u2                     // points to the inside of the turn
            let sharpness = hypot(bisector.x, bisector.y) / 2        // 0 = straight, 1 = reversal
            turn[i] = sharpness
            if sharpness < 0.2 {
                // Nearly collinear: the finger doesn't aim at the letter, it just passes over it.
                let p = project(via[i], onto: via[i - 1], via[i + 1])
                via[i] = CGPoint(x: p.x + gaussian(&rng) * kw * 0.05, y: p.y + gaussian(&rng) * kh * 0.05)
            } else {
                let cut = style.cornerCut * kw * min(1, sharpness * 1.4)
                let dir = unit(bisector)
                via[i] = CGPoint(x: via[i].x + dir.x * cut, y: via[i].y + dir.y * cut)
            }
        }
        // Lift-off: overshoot or stop short along the incoming direction.
        let inDir = unit(keys[n - 1].center - via[n - 2])
        let across = CGPoint(x: -inDir.y, y: inDir.x)
        via[n - 1] = CGPoint(x: via[n - 1].x + inDir.x * style.endAlong * kw + across.x * style.endAcross * kw,
                             y: via[n - 1].y + inDir.y * style.endAlong * kw + across.y * style.endAcross * kw)

        // 3. Polyline through the via points with every corner rounded by a quadratic Bézier: a
        //    finger slows into a turn and cuts it, but never bulges outwards like a spline would.
        var fine: [CGPoint] = [via[0]]
        var viaIndex: [Int] = [0]                      // index into `fine` of every via point
        func appendLine(to p: CGPoint) {
            let a = fine[fine.count - 1]
            let steps = max(1, Int(distance(a, p)))
            for k in 1...steps {
                let f = CGFloat(k) / CGFloat(steps)
                fine.append(CGPoint(x: a.x + (p.x - a.x) * f, y: a.y + (p.y - a.y) * f))
            }
        }
        for i in 1..<n {
            if i == n - 1 {
                appendLine(to: via[i])
                viaIndex.append(fine.count - 1)
                break
            }
            let a = via[i - 1], b = via[i], c = via[i + 1]
            let r = min(style.filletRadius * kw, distance(a, b) * 0.45, distance(b, c) * 0.45)
            let u1 = unit(a - b), u2 = unit(c - b)
            let enter = b + u1 * r, exit = b + u2 * r
            appendLine(to: enter)
            let steps = max(4, Int(r * 2))
            var closest = fine.count - 1
            for k in 1...steps {
                let t = CGFloat(k) / CGFloat(steps)
                let p = CGPoint(x: (1 - t) * (1 - t) * enter.x + 2 * (1 - t) * t * b.x + t * t * exit.x,
                                y: (1 - t) * (1 - t) * enter.y + 2 * (1 - t) * t * b.y + t * t * exit.y)
                fine.append(p)
                if k == steps / 2 { closest = fine.count - 1 }
            }
            viaIndex.append(closest)
        }
        // Arc length along the fine path.
        var arc = [CGFloat](repeating: 0, count: fine.count)
        for i in 1..<fine.count { arc[i] = arc[i - 1] + distance(fine[i], fine[i - 1]) }
        let total = arc[arc.count - 1]

        // 4. Occasional wobble: a lateral bump over one to two key widths.
        if style.wobble > 0, total > kw * 2 {
            let span = kw * (1 + rng.unit())
            let s0 = rng.unit() * max(0, total - span)
            for i in 1..<(fine.count - 1) where arc[i] >= s0 && arc[i] <= s0 + span {
                let d = unit(fine[i + 1] - fine[i - 1])
                let bump = sin((arc[i] - s0) / span * .pi) * style.wobble * kw
                fine[i] = CGPoint(x: fine[i].x - d.y * bump, y: fine[i].y + d.x * bump)
            }
        }

        // 5. Speed profile: fast on straight runs, slow in turns, accelerating after touch-down
        //    and braking before lift-off.
        let viaArc = viaIndex.map { arc[$0] }
        let turnWidth = kw * 0.6
        func speed(at s: CGFloat) -> CGFloat {
            var v = style.peakSpeed
            for i in 1..<(n - 1) where turn[i] > 0.2 {
                let d = (s - viaArc[i]) / turnWidth
                v *= 1 - style.turnSlowdown * min(1, turn[i] * 1.3) * exp(-0.5 * d * d)
            }
            v *= 0.3 + 0.7 * min(1, s / (kw * 0.8))
            v *= 0.35 + 0.65 * min(1, (total - s) / (kw * 0.8))
            return max(v, 60)
        }

        // 6. Sample at the touch rate; dwell on double letters.
        let dt = 1 / style.sampleRate
        var out: [Sample] = []
        var s: CGFloat = 0, t: TimeInterval = 0, j = 0
        var nextVia = 1
        func point(at s: CGFloat) -> CGPoint {
            while j + 1 < arc.count && arc[j + 1] < s { j += 1 }
            guard j + 1 < arc.count else { return fine[fine.count - 1] }
            let f = (s - arc[j]) / max(arc[j + 1] - arc[j], 1e-6)
            return CGPoint(x: fine[j].x + (fine[j + 1].x - fine[j].x) * f, y: fine[j].y + (fine[j + 1].y - fine[j].y) * f)
        }
        func emit(_ p: CGPoint) {
            out.append(Sample(point: CGPoint(x: p.x + gaussian(&rng) * style.jitter, y: p.y + gaussian(&rng) * style.jitter), time: t))
            t += dt
        }
        for _ in 0..<Int(style.startDwell / dt) { emit(fine[0]) }
        while s < total {
            emit(point(at: s))
            if nextVia < n - 1, s >= viaArc[nextVia] {
                if keys[nextVia].doubled && style.doubleLetterDwell > 0 {
                    let p = point(at: s)
                    for _ in 0..<Int(style.doubleLetterDwell / dt) { emit(p) }
                }
                nextVia += 1
            }
            s += speed(at: s) * CGFloat(dt)
        }
        emit(fine[fine.count - 1])
        for _ in 0..<Int(style.endDwell / dt) { emit(fine[fine.count - 1]) }
        if style.liftHook > 0 {
            // Fingers often curl a little (mostly downwards, towards the space bar) as they lift.
            let last = out[out.count - 1].point
            let dir = unit(CGPoint(x: rng.jitter(1), y: 0.6 + 0.4 * rng.unit()))
            for k in 1...2 {
                emit(CGPoint(x: last.x + dir.x * style.liftHook * CGFloat(k) / 2, y: last.y + dir.y * style.liftHook * CGFloat(k) / 2))
            }
        }
        return out
    }

    // MARK: Geometry helpers

    private func gaussian(_ rng: inout TestSupport.SplitMix) -> CGFloat {
        let u1 = max(rng.unit(), 1e-4), u2 = rng.unit()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func unit(_ v: CGPoint) -> CGPoint {
        let l = hypot(v.x, v.y)
        return l > 1e-6 ? CGPoint(x: v.x / l, y: v.y / l) : .zero
    }

    private func project(_ p: CGPoint, onto a: CGPoint, _ b: CGPoint) -> CGPoint {
        let ab = b - a
        let l2 = ab.x * ab.x + ab.y * ab.y
        guard l2 > 1e-6 else { return a }
        let t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / l2))
        return CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
    }
}

private func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
private func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
