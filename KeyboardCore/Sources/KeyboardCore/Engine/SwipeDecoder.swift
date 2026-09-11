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
/// finger path in two channels: **location** (where on the keyboard, in key widths, via banded DTW)
/// and **shape** (scale/translation-invariant outline). Both channels are Gaussian log-likelihoods
/// that are summed with the unigram/bigram prior.
public final class SwipeDecoder {

    public struct Parameters: Sendable {
        public var sampleCount = 32
        /// Radii (in key widths) around the first/last touch point that pick candidate start/end letters.
        public var startRadius: Float = 1.35
        public var endRadius: Float = 1.6
        public var maxStartKeys = 4
        public var maxEndKeys = 5
        /// Standard deviations of the two channels.
        public var sigmaLocation: Float = 0.5      // key widths
        public var sigmaShape: Float = 0.15        // unit box
        /// Weight of the language-model log-probability.
        public var languageWeight: Float = 0.45
        /// Penalty per key width that the start/end points miss the first/last key centre.
        public var endpointWeight: Float = 1.6
        /// Penalty weight for ideal keys the finger never came near ("tunnel" check).
        public var visitWeight: Float = 2.5
        /// Distance (key widths) within which a key counts as visited.
        public var visitTolerance: Float = 0.5
        public var maxCandidatesPerBucket = 900
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
    public func decode(path rawPath: [CGPoint], keyMap: KeyMap, context: DecodeContext = DecodeContext(), limit: Int = 5) -> [SwipeCandidate] {
        let p = parameters
        let kw = Float(keyMap.keyWidth)
        var pts = PathGeometry.dedupe(rawPath.map(FPoint.init))
        guard pts.count >= 2 else { return [] }
        pts = PathGeometry.smooth(pts)
        let userLength = PathGeometry.length(pts)
        guard userLength > kw * 0.6 else { return [] }

        let user = PathGeometry.resample(pts, count: p.sampleCount)
        let userShape = PathGeometry.normalizeShape(user)
        let start = user[0], end = user[user.count - 1]
        let centers = keyMap.centers.map(FPoint.init)

        let startKeys = keyMap.nearestCodes(to: CGPoint(x: CGFloat(start.x), y: CGFloat(start.y)), radius: CGFloat(p.startRadius * kw), limit: p.maxStartKeys)
        let endKeys = keyMap.nearestCodes(to: CGPoint(x: CGFloat(end.x), y: CGFloat(end.y)), radius: CGFloat(p.endRadius * kw), limit: p.maxEndKeys)
        guard !startKeys.isEmpty, !endKeys.isEmpty else { return [] }

        let lm = LanguageModel(lexicon: lexicon, user: self.user)
        let prevID = lm.previousID(for: context.previousWord)

        struct Scored { let word: String; let score: Float }
        var scored: [Scored] = []
        scored.reserveCapacity(64)
        var ideal: [FPoint] = []
        ideal.reserveCapacity(24)

        // Pruning thresholds derived from the observed path.
        let minIdeal = userLength * 0.45 - kw * 1.2
        let maxIdeal = userLength * 1.75 + kw * 1.5
        let locationAbort: Float = 2.6 * kw   // mean aligned distance beyond which a word can't win

        @inline(__always)
        func evaluate(codes: ArraySlice<UInt8>, word: String, prior: Float) {
            // Ideal path through key centres.
            ideal.removeAll(keepingCapacity: true)
            for c in codes { ideal.append(centers[Int(c)]) }
            let idealLength = PathGeometry.length(ideal)
            if ideal.count == 1 { return }                       // single-letter words are taps
            if idealLength < minIdeal || idealLength > maxIdeal { return }

            // Endpoint penalty (in key widths). Users are precise at the start, sloppier at the end.
            let ds = start.distance(to: ideal[0]) / kw
            let de = end.distance(to: ideal[ideal.count - 1]) / kw
            let endpointPenalty = p.endpointWeight * (ds * ds + 0.5 * de * de)
            if endpointPenalty > 12 { return }

            let idealSampled = PathGeometry.resample(ideal, count: p.sampleCount)
            let aligned = PathGeometry.alignedDistance(user, idealSampled, abortAbove: locationAbort)
            if aligned == .infinity { return }
            let dtw = PathGeometry.dtwDistance(user, idealSampled, band: p.dtwBand)
            let location = min(aligned, dtw * 1.15) / kw
            let shape = PathGeometry.alignedDistance(userShape, PathGeometry.normalizeShape(idealSampled))

            // Every key of the word must be approached by the finger at some point.
            var visitPenalty: Float = 0
            for k in ideal {
                var best = Float.greatestFiniteMagnitude
                for u in user {
                    let d = k.distance(to: u)
                    if d < best { best = d }
                }
                let miss = max(0, best / kw - p.visitTolerance)
                visitPenalty += miss * miss
            }
            visitPenalty *= p.visitWeight

            let locLL = -0.5 * (location / p.sigmaLocation) * (location / p.sigmaLocation)
            let shapeLL = -0.5 * (shape / p.sigmaShape) * (shape / p.sigmaShape)
            let score = locLL + shapeLL - endpointPenalty - visitPenalty + p.languageWeight * prior
            scored.append(Scored(word: word, score: score))
        }

        var visited = Set<Int32>()
        for s in startKeys {
            for e in endKeys {
                let bucket = lexicon.bucket(first: s.code, last: e.code)
                var n = 0
                for id in bucket {
                    if n >= p.maxCandidatesPerBucket { break }
                    n += 1
                    if !visited.insert(id).inserted { continue }
                    let range = lexicon.swipeCodeRange(id)
                    let prior = lm.logProb(id: id, previousID: prevID, previousWord: context.previousWord)
                    evaluate(codes: lexicon.swipeCodes[range], word: lexicon.word(id), prior: prior)
                }
            }
        }

        if let userLex = self.user {
            let startSet = Set(startKeys.map(\.code)), endSet = Set(endKeys.map(\.code))
            for entry in userLex.swipeEntries where !lexicon.contains(entry.word) {
                guard let f = entry.codes.first, let l = entry.codes.last, startSet.contains(f), endSet.contains(l) else { continue }
                let prior = lm.logProb(userWord: entry.word, previousWord: context.previousWord)
                evaluate(codes: entry.codes[...], word: entry.word, prior: prior)
            }
        }

        guard !scored.isEmpty else { return [] }
        scored.sort { $0.score > $1.score }

        // Distinct spellings only (case-insensitive) – "Sie"/"sie" keep the better-scored casing.
        var seen = Set<String>()
        var top: [Scored] = []
        for s in scored {
            if seen.insert(s.word.lowercased()).inserted {
                top.append(s)
                if top.count == limit { break }
            }
        }
        let maxScore = top[0].score
        let weights = top.map { exp($0.score - maxScore) }
        let z = weights.reduce(0, +)
        return zip(top, weights).map { SwipeCandidate(word: $0.word, score: $0.score, confidence: $1 / z) }
    }
}
