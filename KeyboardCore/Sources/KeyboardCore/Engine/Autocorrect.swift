import Foundation

public struct Correction: Hashable, Sendable {
    public let word: String
    /// Weighted edit distance from the typed text (0 = identical spelling).
    public let distance: Float
    /// Combined log-domain score, higher is better.
    public let score: Float
    /// True when the engine is confident enough to replace the typed word automatically.
    public let autoApply: Bool
}

/// Typo correction and completion ranking for tap typing.
///
/// Costs: substitutions between adjacent keys are cheap (fat fingers), transpositions are cheap
/// (fast typing), the language's digraph spellings ("ue"→"ü", "ss"→"ß" in German) and casing
/// fixes are nearly free.
public final class Autocorrect {

    public struct Parameters: Sendable {
        public var adjacentSubstitution: Float = 0.45
        public var substitution: Float = 1.0
        public var insertion: Float = 0.9
        public var deletion: Float = 0.9
        public var transposition: Float = 0.7
        public var languageWeight: Float = 0.12
        /// Maximum distance to consider, scaled with word length.
        public var maxDistanceShort: Float = 1.0    // ≤ 4 letters
        public var maxDistanceLong: Float = 2.2     // ≥ 8 letters
        public var maxCandidates = 6
        public init() {}
    }

    public let lexicon: Lexicon
    public let keyMap: KeyMap
    public var user: UserLexicon?
    public var parameters: Parameters

    private let adjacency: [Bool]   // count × count

    public init(lexicon: Lexicon, keyMap: KeyMap, user: UserLexicon? = nil, parameters: Parameters = Parameters()) {
        self.lexicon = lexicon
        self.keyMap = keyMap
        self.user = user
        self.parameters = parameters
        let n = KeyAlphabet.count
        var adj = [Bool](repeating: false, count: n * n)
        for a in 0..<n { for b in 0..<n where a != b { adj[a * n + b] = keyMap.areAdjacent(UInt8(a), UInt8(b)) } }
        adjacency = adj
    }

    // MARK: Public API

    /// Candidates for a fully typed word (called when the user hits space/punctuation).
    /// The first element is the best; `autoApply` says whether to replace silently.
    public func corrections(for typed: String, previousWord: String?, isSentenceStart: Bool) -> [Correction] {
        guard !typed.isEmpty, typed.count <= 32 else { return [] }
        let p = parameters
        let lm = LanguageModel(lexicon: lexicon, user: user)
        let prevID = lm.previousID(for: previousWord)
        let typedCodes = KeyAlphabet.codes(typed)
        guard typedCodes.count == typed.count else { return [] }    // digits / symbols: leave alone

        // At a sentence start the first letter is capitalised automatically, so "Wir" is as known as "wir".
        let decapitalized = typed.prefix(1).lowercased() + typed.dropFirst()
        let knownViaSentenceStart = isSentenceStart && typed.first?.isUppercase == true && lexicon.contains(decapitalized)

        var results: [String: (distance: Float, prior: Float)] = [:]
        func offer(_ word: String, distance: Float, prior: Float) {
            if knownViaSentenceStart && word == decapitalized { return }   // "Das" must not become "das"
            if let existing = results[word], existing.distance <= distance { return }
            results[word] = (distance, prior)
        }

        // 1. Exact / casing / digraph matches.
        let typedIsKnown = lexicon.contains(typed) || knownViaSentenceStart || (user?.isLearned(typed) ?? false)
        if knownViaSentenceStart {
            offer(typed, distance: 0, prior: prior(of: decapitalized, lm: lm, prevID: prevID, previous: previousWord))
        }
        for casing in lexicon.casings(of: typed) where !(knownViaSentenceStart && casing == decapitalized) {
            let d: Float = casing == typed ? 0 : 0.2
            offer(casing, distance: d, prior: prior(of: casing, lm: lm, prevID: prevID, previous: previousWord))
        }
        for variant in lexicon.language.rules.spellingVariants(typed) {
            for casing in lexicon.casings(of: variant) {
                offer(casing, distance: 0.15, prior: prior(of: casing, lm: lm, prevID: prevID, previous: previousWord))
            }
        }
        if let user {
            if user.isLearned(typed) { offer(typed, distance: 0, prior: lm.logProb(userWord: typed, previousWord: previousWord)) }
        }

        // 2. Fuzzy matches over the lexicon.
        let maxDistance = maxDistance(forLength: typed.count)
        let firstCandidates = neighbours(of: typedCodes[0])
        let lastCandidates = neighbours(of: typedCodes[typedCodes.count - 1])
        var dp = EditDistance(capacity: 34)
        var seen = Set<Int32>()
        let lengthSlack = typed.count <= 4 ? 1 : 2

        for f in firstCandidates {
            for l in lastCandidates + [nil] {
                // nil = any last letter (covers trailing insertions/deletions) but only same first letter.
                if l == nil && f != typedCodes[0] { continue }
                let buckets: [ArraySlice<Int32>] = l.map { [lexicon.bucket(first: f, last: $0)] }
                    ?? (0..<UInt8(KeyAlphabet.count)).map { lexicon.bucket(first: f, last: $0) }
                for bucket in buckets {
                    var n = 0
                    for id in bucket {
                        n += 1
                        if n > 1200 { break }
                        if !seen.insert(id).inserted { continue }
                        let range = lexicon.letterCodeRange(id)
                        if abs(range.count - typedCodes.count) > lengthSlack { continue }
                        var d = dp.distance(typedCodes, lexicon.letterCodes[range], adjacency: adjacency, p: p, abortAbove: maxDistance)
                        if d <= maxDistance {
                            let w = lexicon.word(id)
                            d += casingPenalty(typed: typed, candidate: w, isSentenceStart: isSentenceStart)
                            offer(w, distance: d, prior: lm.logProb(id: id, previousID: prevID, previousWord: previousWord))
                        }
                    }
                }
            }
        }

        // Personal words.
        if let user {
            for entry in user.swipeEntries {
                let codes = entry.letterCodes
                guard abs(codes.count - typedCodes.count) <= lengthSlack, !codes.isEmpty else { continue }
                var d = dp.distance(typedCodes, codes[...], adjacency: adjacency, p: p, abortAbove: maxDistance)
                if d <= maxDistance {
                    d += casingPenalty(typed: typed, candidate: entry.word, isSentenceStart: isSentenceStart)
                    offer(entry.word, distance: d, prior: lm.logProb(userWord: entry.word, previousWord: previousWord))
                }
            }
        }

        guard !results.isEmpty else { return [] }

        // 3. Rank: distance dominates, language model breaks ties and rescues common words.
        var ranked = results.map { (word: $0.key, distance: $0.value.distance, score: -$0.value.distance + p.languageWeight * $0.value.prior) }
        ranked.sort { $0.score > $1.score }
        ranked = Array(ranked.prefix(p.maxCandidates))

        let best = ranked[0]
        // Accents reached via long-press are deliberate ("Má", "café"): suggest, never replace.
        let hasDeliberateDiacritics = typed.contains(where: KeyAlphabet.isFoldedLetter)
        let typedPrior = lexicon.logProbability(of: typed)
        let typedLowerKnown = lexicon.containsIgnoringCase(typed)
        var autoApply = false
        if best.word != typed && !hasDeliberateDiacritics {
            if best.distance <= 0.2 {
                // casing / digraph fix – but never when the typed casing is itself a real word ("essen").
                autoApply = !typedIsKnown
            } else if !typedIsKnown && !typedLowerKnown && !(user?.isBlocked(typed) ?? false) {
                let strong = best.distance <= 1.0 || (typed.count >= 6 && best.distance <= 1.6)
                // The margin is measured against a genuinely different word, not the other casing of the same one.
                let runnerUp = ranked.dropFirst().first { $0.word.lowercased() != best.word.lowercased() }
                let margin = runnerUp.map { best.score - $0.score } ?? 10
                autoApply = strong && margin > 0.15 && best.score - (-3.0 + p.languageWeight * typedPrior) > 0 && typed.count >= 3
            }
        }
        return ranked.enumerated().map { i, r in
            Correction(word: r.word, distance: r.distance, score: r.score, autoApply: i == 0 && autoApply)
        }
    }

    /// Whether `word` should be flagged as unknown (for the "learn?" affordance).
    public func isKnown(_ word: String) -> Bool {
        lexicon.containsIgnoringCase(word) || (user?.isLearned(word) ?? false)
    }

    // MARK: Helpers

    private func prior(of word: String, lm: LanguageModel, prevID: Int32?, previous: String?) -> Float {
        if let id = lexicon.id(exact: word) { return lm.logProb(id: id, previousID: prevID, previousWord: previous) }
        return lm.logProb(userWord: word, previousWord: previous)
    }

    /// A candidate whose initial casing differs from what the user typed costs a little, so
    /// "morgem" → "morgen" rather than "Morgen". Free at sentence start, where shift is implicit.
    private func casingPenalty(typed: String, candidate: String, isSentenceStart: Bool) -> Float {
        guard let t = typed.first, let c = candidate.first else { return 0 }
        if t.isUppercase == c.isUppercase { return 0 }
        if isSentenceStart && t.isUppercase { return 0 }
        return 0.2
    }

    private func maxDistance(forLength n: Int) -> Float {
        let p = parameters
        if n <= 4 { return p.maxDistanceShort }
        if n >= 8 { return p.maxDistanceLong }
        return p.maxDistanceShort + (p.maxDistanceLong - p.maxDistanceShort) * Float(n - 4) / 4
    }

    private func neighbours(of code: UInt8) -> [UInt8] {
        let n = KeyAlphabet.count
        var out: [UInt8] = [code]
        for b in 0..<n where adjacency[Int(code) * n + b] { out.append(UInt8(b)) }
        return out
    }
}

/// Reusable Damerau–Levenshtein buffer with keyboard-aware substitution costs.
struct EditDistance {
    private var rows: [[Float]]

    init(capacity: Int) {
        rows = [[Float]](repeating: [Float](repeating: 0, count: capacity + 1), count: capacity + 1)
    }

    mutating func distance(_ a: [UInt8], _ b: ArraySlice<UInt8>, adjacency: [Bool], p: Autocorrect.Parameters, abortAbove: Float) -> Float {
        let n = a.count, m = b.count
        guard n <= rows.count - 1, m <= rows.count - 1 else { return .infinity }
        let bStart = b.startIndex
        let k = KeyAlphabet.count
        for j in 0...m { rows[0][j] = Float(j) * p.insertion }
        for i in 1...n {
            rows[i][0] = Float(i) * p.deletion
            var rowMin = rows[i][0]
            let ai = a[i - 1]
            for j in 1...m {
                let bj = b[bStart + j - 1]
                var cost: Float
                if ai == bj {
                    cost = rows[i - 1][j - 1]
                } else {
                    let sub = adjacency[Int(ai) * k + Int(bj)] ? p.adjacentSubstitution : p.substitution
                    cost = rows[i - 1][j - 1] + sub
                }
                cost = min(cost, rows[i - 1][j] + p.deletion, rows[i][j - 1] + p.insertion)
                if i > 1 && j > 1 && ai == b[bStart + j - 2] && a[i - 2] == bj {
                    cost = min(cost, rows[i - 2][j - 2] + p.transposition)
                }
                rows[i][j] = cost
                rowMin = min(rowMin, cost)
            }
            if rowMin > abortAbove { return .infinity }
        }
        return rows[n][m]
    }
}
