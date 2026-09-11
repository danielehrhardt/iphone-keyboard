import Foundation

/// Interpolated unigram/bigram scoring shared by swipe decoding, autocorrect and prediction.
public struct LanguageModel {
    public let lexicon: Lexicon
    public let user: UserLexicon?

    public init(lexicon: Lexicon, user: UserLexicon? = nil) {
        self.lexicon = lexicon
        self.user = user
    }

    /// log P(word | previous). Mixes bigram evidence (static + personal) with the unigram prior.
    public func logProb(id: Int32, previousID: Int32?, previousWord: String?) -> Float {
        let uni = lexicon.logProb[Int(id)]
        var best = uni
        if let previousID, let bi = lexicon.bigramLogProb(previous: previousID, next: id) {
            best = logAdd(log(0.65) + bi, log(0.35) + uni)
        }
        if let user, let previousWord {
            let word = lexicon.word(id)
            if let boost = user.bigramLogBoost(previous: previousWord, next: word) {
                best = max(best, logAdd(best, boost))
            }
        }
        if let user {
            let word = lexicon.word(id)
            if let b = user.unigramLogBoost(word) { best = logAdd(best, b) }
        }
        return best
    }

    /// Score for a word that only exists in the personal dictionary.
    public func logProb(userWord: String, previousWord: String?) -> Float {
        guard let user else { return lexicon.minLogProb }
        var lp = user.unigramLogBoost(userWord) ?? lexicon.minLogProb
        if let previousWord, let b = user.bigramLogBoost(previous: previousWord, next: userWord) {
            lp = logAdd(lp, b)
        }
        return lp
    }

    public func previousID(for word: String?) -> Int32? {
        guard let word, !word.isEmpty else { return nil }
        return lexicon.id(exact: word) ?? lexicon.id(caseInsensitive: word)
    }

    @inline(__always)
    func logAdd(_ a: Float, _ b: Float) -> Float {
        let hi = max(a, b), lo = min(a, b)
        if lo == -.infinity { return hi }
        return hi + log1p(exp(lo - hi))
    }
}
