import Foundation
import CoreGraphics

public struct SwipeCandidate: Hashable, Sendable {
    public let word: String
    /// Log-domain score; higher is better. Only comparable within one decode call.
    public let score: Float
    /// Probability after softmax over the returned list.
    public let confidence: Float
}

public struct DecodeContext: Sendable {
    public var previousWord: String?
    public init(previousWord: String? = nil) { self.previousWord = previousWord }
}

/// Gesture ("glide") typing decoder in the spirit of SHARK², with a language-model prior.
///
/// Every candidate word is turned into an ideal path through its key centres and compared with the
/// finger path in two channels: **location** (where on the keyboard, via banded DTW) and **shape**
/// (scale/translation-invariant outline). On top come an in-order "every key visited" check,
/// start/end point terms and a check that every sharp turn of the finger (and, with timestamps,
/// every spot where it lingered) is explained by a letter of the word. All terms are
/// Gaussian-style log-likelihoods summed with the unigram/bigram prior.
///
/// The location and shape evidence grows with the length of the gesture: a long swipe pins the
/// word down far better than a two-letter flick, so it may overrule a much more frequent word,
/// while short gestures lean on the prior.
///
/// Candidates come from the (first letter, last letter) buckets around the start and end of the
/// path and pass increasingly expensive stages (table lookups, a quarter-resolution comparison,
/// the full comparison), each only as long as the word can still reach the current top list.
///
/// `decode` keeps no state between calls, so it may run on a background queue (live preview
/// while the finger moves) at the same time as on the main thread.
public final class SwipeDecoder {

    public struct Parameters: Sendable {
        // MARK: Path

        /// Resampled points for the shortest gestures. Longer ones get `samplesPerKey` points per
        /// key width of path, up to `maxSampleCount`: a fixed count blurs long words and wastes
        /// time on short ones.
        public var sampleCount = 24
        public var samplesPerKey: Float = 2.5
        public var maxSampleCount = 64
        /// Touch points closer than this (key widths) to the previous one are dropped: a resting
        /// finger jitters, and the jitter would otherwise add path length where nothing happens.
        public var minPointSpacing: Float = 0.02

        // MARK: Candidates

        /// Radii (in key widths) around the first/last touch point that pick candidate start/end
        /// letters. Fingers overshoot or lift early, so the end looks further and at more keys;
        /// the distance itself is paid for through `endpointWeight`.
        public var startRadius: Float = 1.35
        public var endRadius: Float = 1.8
        public var maxStartKeys = 4
        public var maxEndKeys = 6
        /// Words per (first, last) bucket, most frequent first. Rejecting a word is cheap, so this
        /// only bounds pathological buckets ("a…n" has over 4000 German words).
        public var maxCandidatesPerBucket = 3000
        /// Words with a key farther than this (key widths) from the whole path are not considered.
        public var visitReject: Float = 1.8
        /// Words whose ideal path is longer or shorter than the finger path by more than this
        /// (log ratio, widened for short paths) are not considered. Cut corners make the finger's
        /// path a little shorter, overshoot and wobble a little longer, never by a factor of two.
        public var lengthSlack: Float = 0.6

        // MARK: Scoring

        /// Standard deviations of the two channels.
        public var sigmaLocation: Float = 0.5      // key widths
        public var sigmaShape: Float = 0.25        // unit box
        /// Growth of the location/shape evidence per key width of path (see the type's comment).
        public var evidencePerKey: Float = 0.25
        /// Largest squared distance (key widths²) a single sample adds to the location cost: a
        /// stray point (a lift-off hook) must not outweigh the rest of the path.
        public var locationCap: Float = 4
        /// Weight of the language-model log-probability.
        public var languageWeight: Float = 0.315
        /// Log-probability a word from the personal dictionary gets at least (about a top-3000
        /// word): the user typed it repeatedly, so it is everyday vocabulary for them, although
        /// the personal boost of a word typed twice is that of a very rare word.
        public var personalWordLogProb: Float = -10.5
        /// Penalty per squared key width that the start/end points miss the first/last key centre.
        public var endpointWeight: Float = 1.6
        /// Relative weight of the end point: users are precise at the start, sloppier at the end.
        public var endpointEndRatio: Float = 0.5
        /// Penalty weight for keys the finger never came near, visited in the word's order (so
        /// "Wasser" needs the path to pass a, s, e, r in that order, not just somewhere).
        public var visitWeight: Float = 0.625
        /// Distance (key widths) within which a key counts as visited.
        public var visitTolerance: Float = 0.7
        /// Penalty for sharp turns of the finger (and, with timestamps, spots where it lingered)
        /// that no letter of the word explains: people turn and slow down at letters.
        public var cornerWeight: Float = 2.0
        /// With timestamps, a spot where the finger spent this many times the average time per
        /// stretch of path counts as a corner.
        public var pauseThreshold: Float = 2.5

        // MARK: Speed

        /// A candidate whose quarter-resolution location cost exceeds what it could still afford
        /// by this factor is dropped before the full comparison (0 disables the shortcut).
        public var coarseMargin: Float = 1.3
        /// DTW band: a fraction of the sample count, at least `dtwBand` samples.
        public var dtwBandFraction: Float = 0.125
        public var dtwBand = 4

        public init() {}
    }

    public let lexicon: Lexicon
    public var user: UserLexicon?
    public var parameters: Parameters

    public init(lexicon: Lexicon, user: UserLexicon? = nil, parameters: Parameters = Parameters()) {
        self.lexicon = lexicon
        self.user = user
        self.parameters = parameters
    }

    /// Decodes a finger path (in the same coordinate space as `keyMap`). Returns the best `limit`
    /// distinct words, best first. Empty if the gesture is too short to be a swipe.
    ///
    /// `timestamps` (seconds, one per path point, e.g. `UITouch.timestamp` of every coalesced
    /// touch) are optional; with them, spots where the finger slowed down count as letters.
    public func decode(path rawPath: [CGPoint], keyMap: KeyMap, timestamps: [TimeInterval]? = nil,
                       context: DecodeContext = DecodeContext(), limit: Int = 5) -> [SwipeCandidate] {
        guard limit > 0, let gesture = Gesture(path: rawPath, timestamps: timestamps, keyMap: keyMap, parameters: parameters) else { return [] }
        let p = parameters
        let lm = LanguageModel(lexicon: lexicon, user: self.user, personalFloor: p.personalWordLogProb)
        let prevID = lm.previousID(for: context.previousWord)
        var scorer = Scorer(gesture: gesture, parameters: p)

        struct Scored { let word: String; let score: Float }
        var scored: [Scored] = []
        scored.reserveCapacity(64)
        // Scores of the best few so far, descending: anything that can't beat the last one is skipped.
        var top: [Float] = []
        let keep = limit + 4
        func threshold() -> Float { top.count < keep ? -.infinity : top[top.count - 1] }
        func record(_ word: String, _ score: Float) {
            scored.append(Scored(word: word, score: score))
            if top.count < keep || score > top[top.count - 1] {
                var i = top.count
                while i > 0 && top[i - 1] < score { i -= 1 }
                top.insert(score, at: i)
                if top.count > keep { top.removeLast() }
            }
        }

        for s in gesture.startKeys {
            for e in gesture.endKeys {
                let bucket = lexicon.bucket(first: s, last: e)
                var n = 0
                for id in bucket {
                    if n >= p.maxCandidatesPerBucket { break }
                    n += 1
                    let codes = lexicon.swipeCodes[lexicon.swipeCodeRange(id)]
                    guard let bound = scorer.prefilter(codes) else { continue }
                    let prior = lm.logProb(id: id, previousID: prevID, previousWord: context.previousWord)
                    let floor = threshold() - p.languageWeight * prior
                    guard bound > floor, let geo = scorer.geometry(codes, floor: floor) else { continue }
                    record(lexicon.word(id), geo + p.languageWeight * prior)
                }
            }
        }

        if let userLex = self.user {
            let startSet = Set(gesture.startKeys), endSet = Set(gesture.endKeys)
            // Most learned words are dictionary words (scored above); the cheap first/last-key
            // test runs before the dictionary lookup.
            for entry in userLex.swipeEntries {
                guard let f = entry.codes.first, let l = entry.codes.last, startSet.contains(f), endSet.contains(l) else { continue }
                let codes = entry.codes[...]
                guard let bound = scorer.prefilter(codes), !lexicon.contains(entry.word) else { continue }
                let prior = lm.logProb(userWord: entry.word, previousWord: context.previousWord)
                let floor = threshold() - p.languageWeight * prior
                guard bound > floor, let geo = scorer.geometry(codes, floor: floor) else { continue }
                record(entry.word, geo + p.languageWeight * prior)
            }
        }

        guard !scored.isEmpty else { return [] }
        scored.sort { $0.score > $1.score }

        // Distinct spellings only (case-insensitive) – "Sie"/"sie" keep the better-scored casing.
        var seen = Set<String>()
        var best: [Scored] = []
        for s in scored {
            if seen.insert(s.word.lowercased()).inserted {
                best.append(s)
                if best.count == limit { break }
            }
        }
        let maxScore = best[0].score
        let weights = best.map { exp($0.score - maxScore) }
        let z = weights.reduce(0, +)
        return zip(best, weights).map { SwipeCandidate(word: $0.word, score: $0.score, confidence: $1 / z) }
    }
}

// MARK: - Gesture

/// The finger path, prepared once per decode: resampled, in key-width units, with the distance of
/// every key to every sample precomputed (candidate checks then become table lookups).
struct Gesture {
    let n: Int
    let points: [FPoint]
    /// The same path at a quarter of the resolution, for a quick first look at each candidate.
    let coarse: [FPoint]
    let shape: [FPoint]
    /// Path length in key widths.
    let length: Float
    let centers: [FPoint]
    /// Distance of key `code` to sample `t` at `code * n + t`.
    let keyDistance: [Float]
    /// Distance of every key to the closest sample.
    let keyMinDistance: [Float]
    let startKeys: [UInt8]
    let endKeys: [UInt8]
    /// Samples where the finger slowed down or turned sharply; a letter should be near each.
    let corners: [Int]

    init?(path rawPath: [CGPoint], timestamps: [TimeInterval]?, keyMap: KeyMap, parameters p: SwipeDecoder.Parameters) {
        let kw = Float(keyMap.keyWidth)
        let scale = 1 / kw
        // Drop near-duplicate points; with timestamps, remember when each kept point was reached.
        let times = timestamps.flatMap { $0.count == rawPath.count ? $0 : nil }
        var pts: [FPoint] = []
        var reached: [TimeInterval] = []
        pts.reserveCapacity(rawPath.count)
        for (i, cg) in rawPath.enumerated() {
            let q = FPoint(Float(cg.x) * scale, Float(cg.y) * scale)
            if let last = pts.last, last.distance(to: q) < p.minPointSpacing { continue }
            pts.append(q)
            if let times { reached.append(times[i]) }
        }
        guard pts.count >= 2 else { return nil }
        if let last = times?.last { reached.append(last) }            // lift-off closes the last interval
        pts = PathGeometry.smooth(pts)
        let length = PathGeometry.length(pts)
        guard length > 0.6 else { return nil }
        self.length = length

        n = min(p.maxSampleCount, max(p.sampleCount, Int(length * p.samplesPerKey)))
        points = PathGeometry.resample(pts, count: n)
        coarse = PathGeometry.resample(pts, count: max(8, n / 4))
        shape = PathGeometry.normalizeShape(points)
        centers = keyMap.centers.map { FPoint(Float($0.x) * scale, Float($0.y) * scale) }

        let k = KeyAlphabet.count
        var table = [Float](repeating: 0, count: k * n)
        var mins = [Float](repeating: .greatestFiniteMagnitude, count: k)
        for c in 0..<k {
            let center = centers[c]
            for t in 0..<n {
                let d = center.distance(to: points[t])
                table[c * n + t] = d
                if d < mins[c] { mins[c] = d }
            }
        }
        keyDistance = table
        keyMinDistance = mins

        startKeys = Gesture.keys(near: points[0], keyMap: keyMap, radius: p.startRadius, limit: p.maxStartKeys)
        endKeys = Gesture.keys(near: points[n - 1], keyMap: keyMap, radius: p.endRadius, limit: p.maxEndKeys)
        guard !startKeys.isEmpty, !endKeys.isEmpty else { return nil }

        var corners = Gesture.turns(points)
        if p.pauseThreshold > 0, reached.count == pts.count + 1 {
            for t in Gesture.pauses(path: pts, reached: reached, samples: n, threshold: p.pauseThreshold)
            where !corners.contains(where: { abs($0 - t) <= 2 }) {
                corners.append(t)
            }
        }
        self.corners = corners
    }

    /// Candidate first/last letters: the closest keys within `radius` (key widths) of a sample.
    /// Letters without a key of their own (ä on QWERTY) share their base key, so they come along
    /// with it: "über" starts on the u key.
    static func keys(near point: FPoint, keyMap: KeyMap, radius: Float, limit: Int) -> [UInt8] {
        let kw = keyMap.keyWidth
        let near = keyMap.nearestCodes(to: CGPoint(x: CGFloat(point.x) * kw, y: CGFloat(point.y) * kw),
                                       radius: CGFloat(radius) * kw, limit: limit).map(\.code)
        var out = near
        for f in keyMap.foldedCodes.sorted() {
            if let base = KeyAlphabet.baseCode(for: f), near.contains(base) { out.append(f) }
        }
        return out
    }

    /// Interior samples where the direction changes sharply: the finger turned at a letter.
    static func turns(_ points: [FPoint]) -> [Int] {
        let n = points.count
        let w = max(2, n / 16)
        guard n > 2 * w + 2 else { return [] }
        var out: [Int] = []
        var turn = [Float](repeating: 0, count: n)
        for t in w..<(n - w) {
            let a = points[t] - points[t - w], b = points[t + w] - points[t]
            let la = a.length, lb = b.length
            guard la > 1e-4, lb > 1e-4 else { continue }
            let cos = (a.x * b.x + a.y * b.y) / (la * lb)
            turn[t] = 1 - cos          // 0 straight, 1 right angle, 2 reversal
        }
        for t in w..<(n - w) where turn[t] > 0.9 && turn[t] >= turn[t - 1] && turn[t] > turn[t + 1] {
            out.append(t)
        }
        return out
    }

    /// Interior samples where the finger lingered: local maxima of the time spent per stretch of
    /// path, at least `threshold` times the gesture's average. Touch-down and lift-off rests
    /// (the first and last key width) are left to the endpoint terms. `reached[i]` is when
    /// `path[i]` was reached; the last entry is the lift-off time.
    static func pauses(path: [FPoint], reached: [TimeInterval], samples n: Int, threshold: Float) -> [Int] {
        var arc: Float = 0
        var total: Float = 0
        for i in 1..<path.count { total += path[i].distance(to: path[i - 1]) }
        guard total > 0, n > 4 else { return [] }
        let step = total / Float(n - 1)
        var dwell = [Float](repeating: 0, count: n)
        var sum: Float = 0
        for i in 0..<path.count {
            let seg = i + 1 < path.count ? path[i + 1].distance(to: path[i]) : 0
            // A long silence (the app stalled) is not a pause the user made.
            let dt = Float(min(max(reached[i + 1] - reached[i], 0), 0.25))
            let bin = min(n - 1, Int((arc + seg / 2) / step + 0.5))
            dwell[bin] += dt
            sum += dt
            arc += seg
        }
        guard sum > 0 else { return [] }
        // Light smoothing: sample times alias against the resampling grid.
        var smoothed = dwell
        for t in 1..<(n - 1) { smoothed[t] = 0.25 * dwell[t - 1] + 0.5 * dwell[t] + 0.25 * dwell[t + 1] }
        let mean = sum / Float(n)
        let edge = max(1, Int(1 / step + 0.5))
        guard n - edge > edge else { return [] }
        var out: [Int] = []
        for t in edge..<(n - edge) where smoothed[t] >= threshold * mean
            && smoothed[t] >= smoothed[t - 1] && smoothed[t] > smoothed[t + 1] {
            out.append(t)
        }
        return out
    }
}

// MARK: - Scoring

/// Per-decode scratch buffers and the scoring of one candidate against the gesture.
struct Scorer {
    let g: Gesture
    let p: SwipeDecoder.Parameters
    var ideal: [FPoint] = []
    var sampled: [FPoint] = []
    var coarseSampled: [FPoint] = []
    var shape: [FPoint] = []
    var rows: [Float] = []
    var dp: [Float] = []
    let evidence: Float
    let cap: Float              // see `Parameters.locationCap`
    // Terms of the word last passed to `prefilter`.
    var visitCost: Float = 0
    var endpointCost: Float = 0
    var cornerCost: Float = 0
    /// Plausible log(ideal length / path length); short paths vary more (endpoint slop).
    let lengthRange: ClosedRange<Float>

    init(gesture: Gesture, parameters: SwipeDecoder.Parameters) {
        g = gesture
        p = parameters
        evidence = 1 + parameters.evidencePerKey * gesture.length
        cap = parameters.locationCap
        let slack = parameters.lengthSlack * (1 + 2 / max(gesture.length, 1))
        lengthRange = (0.05 - slack)...(0.05 + slack)
        ideal.reserveCapacity(32); sampled.reserveCapacity(g.n); shape.reserveCapacity(g.n)
        dp = [Float](repeating: 0, count: g.n)
    }

    /// Cheap checks from the precomputed tables and the key positions. Returns an upper bound of
    /// the geometric score (the terms computed so far; the others are ≤ 0), or nil to reject.
    mutating func prefilter(_ codes: ArraySlice<UInt8>) -> Float? {
        guard codes.count >= 2 else { return nil }                    // single letters are taps
        for c in codes where g.keyMinDistance[Int(c)] > p.visitReject { return nil }
        let first = g.centers[Int(codes.first!)], last = g.centers[Int(codes.last!)]
        let ds = first.squaredDistance(to: g.points[0]), de = last.squaredDistance(to: g.points[g.n - 1])
        endpointCost = p.endpointWeight * (ds + p.endpointEndRatio * de)
        if endpointCost > 12 { return nil }

        // Path length far off the ideal one: see `Parameters.lengthSlack`.
        ideal.removeAll(keepingCapacity: true)
        for c in codes { ideal.append(g.centers[Int(c)]) }
        let ratio = log(max(PathGeometry.length(ideal), 0.3) / max(g.length, 0.3))
        if ratio > lengthRange.upperBound || ratio < lengthRange.lowerBound { return nil }

        cornerCost = 0
        if p.cornerWeight > 0 && !g.corners.isEmpty {
            let n = g.n, tol = p.visitTolerance
            for t in g.corners {
                var best = Float.greatestFiniteMagnitude
                for c in codes { best = min(best, g.keyDistance[Int(c) * n + t]) }
                let miss = max(0, best - tol)
                cornerCost += miss * miss
            }
            cornerCost *= p.cornerWeight
        }
        return -endpointCost - cornerCost
    }

    /// Cheapest in-order assignment of the word's keys to samples: Σ max(0, d − tolerance)².
    mutating func inOrderVisit(_ codes: ArraySlice<UInt8>) -> Float {
        let n = g.n, tol = p.visitTolerance
        return g.keyDistance.withUnsafeBufferPointer { table -> Float in
            dp.withUnsafeMutableBufferPointer { best -> Float in
                var first = true
                for c in codes {
                    let row = Int(c) * n
                    var running = Float.greatestFiniteMagnitude
                    for t in 0..<n {
                        let miss = max(0, table[row + t] - tol)
                        let cost = miss * miss + (first ? 0 : best[t])
                        if cost < running { running = cost }
                        best[t] = running           // best cost with this key at or before t
                    }
                    first = false
                }
                return best[n - 1]
            }
        }
    }

    /// Full geometric score of `codes`, which must be the word last passed to `prefilter`, or nil
    /// once it can't reach `floor`. Cheap stages first, each with the budget the ones before leave.
    mutating func geometry(_ codes: ArraySlice<UInt8>, floor: Float) -> Float? {
        var fixed = -endpointCost - cornerCost
        guard fixed > floor else { return nil }
        // Location: the remaining budget bounds the mean squared distance worth computing.
        let locScale = 0.5 * evidence / (p.sigmaLocation * p.sigmaLocation)

        // A quarter-resolution location estimate first: most candidates are far off and are
        // dropped for a fraction of the full comparison's cost. It tracks the full value
        // closely; the margin covers the difference.
        if p.coarseMargin > 0 {
            let m = g.coarse.count
            PathGeometry.resample(ideal, count: m, into: &coarseSampled)
            let limit = (fixed - floor) / locScale * p.coarseMargin + 0.05
            let a = PathGeometry.alignedSquaredDistance(g.coarse, coarseSampled, cap: cap)
            if a > limit {
                let d = PathGeometry.dtwSquaredDistance(g.coarse, coarseSampled, band: max(2, m / 8), cap: cap, abortAbove: limit, rows: &rows)
                if d > limit { return nil }
            }
        }

        visitCost = p.visitWeight * inOrderVisit(codes)
        fixed -= visitCost
        guard fixed > floor else { return nil }
        let budget = (fixed - floor) / locScale

        PathGeometry.resample(ideal, count: g.n, into: &sampled)
        let aligned = PathGeometry.alignedSquaredDistance(g.points, sampled, cap: cap)
        let band = max(p.dtwBand, Int(Float(g.n) * p.dtwBandFraction))
        let dtw = PathGeometry.dtwSquaredDistance(g.points, sampled, band: band, cap: cap, abortAbove: min(aligned, budget), rows: &rows)
        let location = min(aligned, dtw)
        guard location < budget else { return nil }
        let locLL = -locScale * location

        shape = sampled
        PathGeometry.normalizeShape(&shape)
        let shapeD = PathGeometry.alignedSquaredDistance(g.shape, shape, cap: 1)
        let shapeLL = -0.5 * evidence * shapeD / (p.sigmaShape * p.sigmaShape)
        return fixed + locLL + shapeLL
    }
}
