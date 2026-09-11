import Foundation
import CoreGraphics

/// One-stop facade for the keyboard extension: owns the lexicon, personal dictionary and the
/// three engines. Loading the bundled lexicon takes a few hundred milliseconds, so create it once.
public final class KeyboardEngine {
    public let lexicon: Lexicon
    public let user: UserLexicon
    public let decoder: SwipeDecoder
    public let predictor: Predictor
    private var autocorrectCache: (key: String, value: Autocorrect)?

    public init(lexicon: Lexicon, user: UserLexicon) {
        self.lexicon = lexicon
        self.user = user
        decoder = SwipeDecoder(lexicon: lexicon, user: user)
        predictor = Predictor(lexicon: lexicon, user: user)
    }

    public convenience init(appGroup: String = KeyboardSettings.appGroup) throws {
        try self.init(lexicon: Lexicon.loadBundled(), user: UserLexicon.shared(appGroup: appGroup))
    }

    /// Autocorrect is bound to a key map (adjacency); cache per geometry.
    public func autocorrect(for keyMap: KeyMap) -> Autocorrect {
        let key = "\(keyMap.keyWidth)x\(keyMap.keyHeight)"
        if let c = autocorrectCache, c.key == key { return c.value }
        let a = Autocorrect(lexicon: lexicon, keyMap: keyMap, user: user)
        autocorrectCache = (key, a)
        return a
    }

    public func decodeSwipe(path: [CGPoint], keyMap: KeyMap, previousWord: String?, limit: Int = 4) -> [SwipeCandidate] {
        decoder.decode(path: path, keyMap: keyMap, context: DecodeContext(previousWord: previousWord), limit: limit)
    }
}
