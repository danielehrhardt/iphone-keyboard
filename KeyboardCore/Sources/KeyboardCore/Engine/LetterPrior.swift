import Foundation

/// How likely each letter is to be typed next, indexed by `KeyAlphabet` code. Drives the dynamic
/// hit-target resizing of letter keys: likely keys own a larger share of their surroundings.
public struct LetterPrior: Equatable, Sendable {
    /// Probabilities per letter code, smoothed so no letter is impossible; sums to 1.
    public let probabilities: [Float]

    /// Fraction of the mass spread evenly over all letters, so a dead-centre tap on an
    /// "unexpected" key still wins and a single dominant letter cannot swallow its neighbours.
    public static let smoothing: Float = 0.01

    /// nil when `weights` carry no mass (nothing in the dictionary continues the prefix).
    public init?(weights: [Float]) {
        precondition(weights.count == KeyAlphabet.count)
        let clamped = weights.map { $0.isFinite ? max($0, 0) : 0 }
        let total = clamped.reduce(0, +)
        guard total > 0 else { return nil }
        let floor = total * Self.smoothing
        let norm = total * (1 + Self.smoothing * Float(KeyAlphabet.count))
        probabilities = clamped.map { ($0 + floor) / norm }
    }

    public func probability(of character: Character) -> Float {
        guard let code = KeyAlphabet.code(for: character) else { return 0 }
        return probabilities[Int(code)]
    }

    public func logProbability(code: UInt8) -> Float {
        guard Int(code) < probabilities.count else { return log(Self.smoothing) }
        return log(probabilities[Int(code)])
    }

    public var mostLikely: Character {
        let i = probabilities.indices.max { probabilities[$0] < probabilities[$1] } ?? 0
        return KeyAlphabet.character(for: UInt8(i))
    }
}

extension Lexicon {
    /// Adds the frequency mass of every dictionary word starting with `prefix` to the letter that
    /// follows the prefix in that word. Returns the mass added. Case-insensitive.
    func addNextLetterWeights(prefix: String, to weights: inout [Float]) -> Float {
        if prefix.isEmpty {
            var total: Float = 0
            for (i, w) in firstLetterWeights.enumerated() { weights[i] += w; total += w }
            return total
        }
        return withLowercaseKey(prefix) { key in
            var total: Float = 0
            lowerBytes.withUnsafeBufferPointer { bytes in
                var i = lowerBound(key)
                var visited = 0
                var unsupported = false
                while i < sortedByLower.count, hasPrefix(entry: i, key) {
                    let id = sortedByLower[i]
                    var at = Int(lowerOffsets[i]) + key.count
                    let end = Int(lowerOffsets[i + 1])
                    if at < end, let code = KeyAlphabet.code(utf8: UnsafeBufferPointer(rebasing: bytes[0..<end]), at: &at, unsupported: &unsupported) {
                        let w = exp(logProb[Int(id)])
                        weights[Int(code)] += w
                        total += w
                    }
                    i += 1
                    visited += 1
                    if visited > 40_000 { break }
                }
            }
            return total
        }
    }
}

extension Predictor {
    /// Interpolation weight of the bigram evidence, mirroring `LanguageModel`.
    static let bigramWeight: Float = 0.65

    /// The next-letter distribution after `prefix` (the word being typed, may be empty) given the
    /// previous word. Combines dictionary completions weighted by frequency, the bigram successors
    /// of `previous` and the personal dictionary. nil when nothing is known about the prefix.
    public func letterPrior(prefix: String, previous: String?) -> LetterPrior? {
        var unigram = [Float](repeating: 0, count: KeyAlphabet.count)
        var bigram = [Float](repeating: 0, count: KeyAlphabet.count)
        _ = lexicon.addNextLetterWeights(prefix: prefix, to: &unigram)
        let lowerPrefix = prefix.lowercased()

        func add(_ word: String, weight: Float, to weights: inout [Float]) {
            let lower = word.lowercased()
            guard lower.hasPrefix(lowerPrefix), lower.count > lowerPrefix.count else { return }
            let next = lower[lower.index(lower.startIndex, offsetBy: lowerPrefix.count)]
            guard let code = KeyAlphabet.code(for: next) else { return }
            weights[Int(code)] += weight
        }

        if let user {
            for w in user.completions(prefix: prefix, limit: 20) {
                add(w, weight: exp(user.unigramLogBoost(w) ?? lexicon.minLogProb), to: &unigram)
            }
        }
        if let previous, !previous.isEmpty {
            for s in lexicon.successors(of: previous) { add(s.word, weight: exp(s.logProb), to: &bigram) }
            if let user {
                for s in user.successors(of: previous) {
                    add(s.word, weight: exp(user.bigramLogBoost(previous: previous, next: s.word) ?? lexicon.minLogProb), to: &bigram)
                }
            }
        }

        let hasBigram = bigram.contains { $0 > 0 }
        var mixed = unigram
        if hasBigram {
            for i in mixed.indices { mixed[i] = (1 - Self.bigramWeight) * unigram[i] + Self.bigramWeight * bigram[i] }
        }
        return LetterPrior(weights: mixed)
    }
}
