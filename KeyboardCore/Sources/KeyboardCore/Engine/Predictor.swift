import Foundation

/// Next-word and completion suggestions for the suggestion strip.
public final class Predictor {
    public let lexicon: Lexicon
    public var user: UserLexicon?

    /// Fallback shown when nothing is known about the context.
    static let coldStart = ["Ich", "Hallo", "Danke", "Ja", "Nein", "Wir", "Guten", "Alles"]

    public init(lexicon: Lexicon, user: UserLexicon? = nil) {
        self.lexicon = lexicon
        self.user = user
    }

    /// Words likely to follow `previous` (nil for sentence start).
    public func nextWords(after previous: String?, isSentenceStart: Bool, limit: Int = 3) -> [String] {
        var out: [String] = []
        func push(_ w: String) {
            let shown = isSentenceStart ? capitalized(w) : w
            if !out.contains(where: { $0.lowercased() == shown.lowercased() }) { out.append(shown) }
        }
        if let previous, !previous.isEmpty {
            if let user {
                for s in user.successors(of: previous).prefix(2) where s.count >= 2 { push(s.word) }
            }
            for s in lexicon.successors(of: previous) where out.count < limit { push(s.word) }
        }
        if out.count < limit {
            for w in (isSentenceStart ? Self.coldStart : ["und", "ich", "die", "das", "nicht", "auch"]) where out.count < limit { push(w) }
        }
        return Array(out.prefix(limit))
    }

    /// Completions of a partially typed word, ranked by frequency with a bigram boost.
    public func completions(prefix: String, previous: String?, isSentenceStart: Bool, limit: Int = 3) -> [String] {
        guard !prefix.isEmpty else { return [] }
        let lm = LanguageModel(lexicon: lexicon, user: user)
        let prevID = lm.previousID(for: previous)
        var scored: [(String, Float)] = []
        for id in lexicon.completions(prefix: prefix, limit: 40) {
            scored.append((lexicon.word(id), lm.logProb(id: id, previousID: prevID, previousWord: previous)))
        }
        if let user {
            for w in user.completions(prefix: prefix, limit: 5) where !lexicon.contains(w) {
                scored.append((w, lm.logProb(userWord: w, previousWord: previous)))
            }
        }
        scored.sort { $0.1 > $1.1 }
        var out: [String] = []
        let typedUpper = prefix.first?.isUppercase == true
        for (w, _) in scored {
            var shown = w
            // Respect the user's shift: "Hau" → "Haus"; "hau" → "Haus" (nouns keep their capital).
            if typedUpper || isSentenceStart { shown = capitalized(w) }
            if shown.lowercased() == prefix.lowercased() { continue }
            if !out.contains(where: { $0.lowercased() == shown.lowercased() }) { out.append(shown) }
            if out.count == limit { break }
        }
        return out
    }

    func capitalized(_ w: String) -> String {
        guard let f = w.first, f.isLowercase else { return w }
        return f.uppercased() + w.dropFirst()
    }
}
