import UIKit
import os.log
import KeyboardCore

private let inputLog = Logger(subsystem: "de.codext.umlaut.keyboard", category: "input")

/// Everything the keyboard shows besides the keys themselves.
struct InputUIState: Equatable {
    var layer: KeyboardLayer = .letters
    var shift: ShiftState = .off
    var suggestions: [Suggestion] = []
    /// Next-letter distribution for the key grid's dynamic hit targets; nil = plain hit test.
    var letterPrior: LetterPrior?
    /// Learned per-key centre shifts for the key grid's hit test; nil = geometric centres.
    var tapOffsets: TapMap.Offsets?
}

protocol InputControllerDelegate: AnyObject {
    func inputController(_ c: InputController, didUpdate state: InputUIState)
    func inputControllerRequestsGlobe(_ c: InputController)
    func inputControllerRequestsEmoji(_ c: InputController)
    func inputControllerRequestsDismiss(_ c: InputController)
}

/// The text-editing brain: turns key events into document edits, runs autocorrect on word
/// boundaries, commits swipe words, tracks shift state and produces the suggestion strip.
///
/// Built for fast typing: a key event never reads the document (every `UITextDocumentProxy`
/// read is a round trip to the host app – see `history`), updates what the *next* tap depends
/// on – shift state and the hit-target prior – synchronously, and hands the suggestion strip to
/// a background queue so the main thread is free for the next touch within a millisecond or two.
final class InputController {

    private enum Commit: Equatable {
        case swipe(word: String, alternates: [String], autoSpace: Bool)
        case autocorrect(original: String, corrected: String, trigger: String)
        case suggestion(word: String)
    }

    /// nil until the lexicon finished loading; typing works, suggestions/swipe wait for it.
    var engine: KeyboardEngine?
    /// The language being typed: decides sentence rules while the engine is still loading and
    /// must match the engine's language once it is there.
    var language: KeyboardLanguage = .default
    let settings: KeyboardSettings
    private let proxy: TextProxy
    weak var delegate: InputControllerDelegate?
    /// Where the suggestion strip is computed. nil runs it inline before the key event returns
    /// (deterministic, for tests); the coordinator sets a serial background queue so a tap costs
    /// the main thread only the edit, the shift state and the hit-target update. Results are
    /// delivered on the main queue; a stale result (an older key event's) is dropped.
    var suggestionQueue: DispatchQueue?

    private(set) var state = InputUIState() { didSet { if state != oldValue { delegate?.inputController(self, didUpdate: state) } } }
    var traits = FieldTraits() { didSet { if traits != oldValue { fieldChanged() } } }
    var keyMap: KeyMap?
    /// Where this user's taps land per key; nil disables learning and adaptive hit targets.
    let tapMap: TapMap?

    private var lastCommit: Commit?
    private var autoSpacePending = false
    private var lastKeyWasSpace = false
    private var shiftTouchedManually = false
    /// The touch behind the key event being handled (nil for events without a point).
    private var currentTouch: CGPoint?
    /// One entry per character of the composing word: the character and where the finger landed
    /// (a non-finite point for characters that did not come from a plain tap). Trusted only when
    /// the characters spell the word being committed; see `learnTaps`.
    private var wordTaps: [(char: Character, point: CGPoint)] = []
    /// True while the last tap-map update came from an autocorrection the user may still revert.
    private var canUndoTapLearning = false
    private static let unknownTap = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
    /// Counts suggestion requests so a result that arrives after a newer request is ignored, and
    /// so a request that is already outdated when the queue reaches it is skipped altogether.
    private let suggestionGeneration = Generation()

    private final class Generation {
        private let lock = NSLock()
        private var value = 0
        /// Bumps and returns the new generation (main thread).
        func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
        var current: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    init(engine: KeyboardEngine?, settings: KeyboardSettings, proxy: TextProxy, tapMap: TapMap? = nil) {
        self.engine = engine
        self.settings = settings
        self.proxy = proxy
        self.tapMap = tapMap
    }

    // MARK: Document context

    /// The text around the cursor. In the extension a proxy read is a round trip to the host
    /// app: it blocks while the host is busy, and right after an edit of ours it may still show
    /// the text from before that edit. So a key event never reads. The keyboard keeps its own
    /// view of the document, advanced locally by every edit it makes, and reads the host only
    /// when the host reports a change (`textDidChangeExternally`).
    private struct DocumentContext: Equatable {
        var before: String
        var after: String
    }

    /// The document as we know it, newest last: the state last read from the host followed by
    /// the state after each of our own edits since. A host report that matches one of these is
    /// the host catching up (a slow host lags several keystrokes behind a fast typist) and
    /// changes nothing; anything else is news and replaces the lot.
    private var history: [DocumentContext] = []
    private static let historyLimit = 64
    /// Set while an edit of ours is in flight, so a host that reports it synchronously (the
    /// in-app text view) is not mistaken for an external change.
    private var isEditing = false

    private var context: DocumentContext {
        if let c = history.last { return c }
        let c = DocumentContext(before: proxy.textBefore, after: proxy.textAfter)
        history = [c]
        return c
    }

    private var textBefore: String { context.before }
    private var textAfter: String { context.after }

    /// Drops what is known about the document; the next key event reads it afresh. For a new
    /// field, which may look just like the last one to `traits`.
    func forgetDocument() { history.removeAll() }

    /// Reads the host and reconciles it with our own view. Returns true when the document differs
    /// from anything we assumed, i.e. someone else changed it.
    private func resync() -> Bool {
        let seen = DocumentContext(before: proxy.textBefore, after: proxy.textAfter)
        if let i = history.lastIndex(of: seen) {
            history.removeFirst(i)
            return false
        }
        history = [seen]
        return true
    }

    private func didEdit(before: String, after: String) {
        history.append(DocumentContext(before: before, after: after))
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }

    private func edit(_ change: (DocumentContext) -> DocumentContext, _ apply: () -> Void) {
        let c = context
        isEditing = true
        apply()
        isEditing = false
        let new = change(c)
        didEdit(before: new.before, after: new.after)
    }

    private func insertText(_ text: String) {
#if DEBUG
        inputLog.debug("insert \(text, privacy: .public)")
#endif
        edit({ DocumentContext(before: $0.before + text, after: $0.after) }) { proxy.insert(text) }
    }

    private func deleteBackwardOnce() {
        delete(count: 1)
    }

    // MARK: Context helpers

    private static let wordCharacters: (Character) -> Bool = { $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }
    private static let openingDelimiters: Set<Character> = LanguageRules.openingDelimiters.union(["'", "/", "-", "#", "@"])
    private static let sentenceTerminators = LanguageRules.sentenceTerminators

    /// The word being typed (letters immediately before the cursor).
    var composingWord: String {
        let before = textBefore
        var start = before.endIndex
        while start > before.startIndex {
            let c = before[before.index(before: start)]
            if !Self.wordCharacters(c) { break }
            start = before.index(before: start)
        }
        // Only when the cursor is at the end of the word.
        if let next = textAfter.first, Self.wordCharacters(next) { return "" }
        return String(before[start...])
    }

    /// The last complete word before the composing word.
    var previousWord: String? {
        if cursorIsInsideWord { return nil }
        let before = textBefore
        let composing = composingWord
        var text = Substring(before.dropLast(composing.count))
        while let last = text.last, last == " " { text = text.dropLast() }
        guard let last = text.last else { return nil }
        if !Self.wordCharacters(last) { return nil }      // punctuation resets context
        var start = text.endIndex
        while start > text.startIndex, Self.wordCharacters(text[text.index(before: start)]) { start = text.index(before: start) }
        return String(text[start...])
    }

    /// True when a letter follows the cursor directly ("Hal|lo").
    private var cursorIsInsideWord: Bool {
        guard let next = textAfter.first, Self.wordCharacters(next) else { return false }
        return textBefore.last.map(Self.wordCharacters) ?? false
    }

    private var isSentenceStart: Bool {
        language.rules.isSentenceStart(String(textBefore.dropLast(composingWord.count)))
    }

    private var suggestionsAllowed: Bool { traits.allowsSuggestions }
    private var autocorrectAllowed: Bool { settings.autocorrect && traits.allowsAutocorrect }
    /// „Justin-Modus“: every word becomes „Justin“ – in every field, regardless of the autocorrect
    /// toggle, with no literal, alternate or backspace escape.
    private var justinModeActive: Bool { settings.justinMode }

    static let justinWord = "Justin"

    /// „Justin“, or „JUSTIN“ when the typed word was written in all caps.
    private static func justin(matching typed: String) -> String {
        let letters = typed.filter(\.isLetter)
        let allCaps = letters.count > 1 && letters.allSatisfy(\.isUppercase)
        return allCaps ? justinWord.uppercased() : justinWord
    }

    // MARK: Field / external changes

    private func fieldChanged() {
        forgetDocument()
        lastCommit = nil
        autoSpacePending = false
        shiftTouchedManually = false
        wordTaps.removeAll()
        var s = state
        s.layer = initialLayer()
        state = s
        refreshNow()
    }

    private func initialLayer() -> KeyboardLayer {
        switch traits.keyboardType {
        case .numberPad, .asciiCapableNumberPad: return .numberPad
        case .decimalPad: return .decimalPad
        case .phonePad: return .phonePad
        case .numbersAndPunctuation: return .symbols
        default: return .letters
        }
    }

    /// Called when the host reports a text or selection change. Our own edits come back this way
    /// too, possibly several keystrokes late; those are recognised and cost one read, nothing more.
    func textDidChangeExternally() {
        guard !isEditing, resync() else { return }
        if case .swipe(let w, _, let autoSpace) = lastCommit {
            let expected = w + (autoSpace ? " " : "")
            if !textBefore.hasSuffix(expected) { lastCommit = nil; autoSpacePending = false }
        } else if case .autocorrect(_, let corrected, let trigger) = lastCommit, !textBefore.hasSuffix(corrected + trigger) {
            lastCommit = nil
        }
        if autoSpacePending, !textBefore.hasSuffix(" ") { autoSpacePending = false }
        refreshNow()
    }

    /// Recomputes shift and suggestions from the document.
    func refresh() { refreshNow() }

    /// Brings the UI state up to date with the (already snapshotted) document. Shift, the letter
    /// prior and the tap offsets decide how the *next* tap is read, so they are updated before
    /// this returns; the suggestion strip may follow a moment later.
    private func refreshNow() {
        var s = state
        s.shift = computedShift(current: s.shift)
        s.letterPrior = buildLetterPrior()
        s.tapOffsets = buildTapOffsets()
        let input = suggestionInput(layer: s.layer)
        let generation = suggestionGeneration.next()
        // No engine, or a field/layer without a strip: the answer is empty and must show at
        // once (leaving a password field's neighbour's words on screen is not an option).
        guard input.allowed, input.engine != nil, let queue = suggestionQueue else {
            s.suggestions = Self.buildSuggestions(input)
            state = s
            return
        }
        state = s
        let counter = suggestionGeneration
        queue.async { [weak self] in
            // Typing faster than the search runs leaves a backlog; only the newest request matters.
            guard counter.current == generation else { return }
            let suggestions = Self.buildSuggestions(input)
            DispatchQueue.main.async { self?.deliver(suggestions, generation: generation) }
        }
    }

    private func deliver(_ suggestions: [Suggestion], generation: Int) {
        guard generation == suggestionGeneration.current else { return }
        var s = state
        s.suggestions = suggestions
        state = s
    }

    /// The learned centre shifts for the current key layout. Applied in every field (it only
    /// makes taps land where the user aims), learning happens in `learnTaps`.
    private func buildTapOffsets() -> TapMap.Offsets? {
        guard settings.adaptiveTapMap, state.layer == .letters, let tapMap, let keyMap else { return nil }
        return tapMap.offsets(for: keyMap)
    }

    /// What the next letter is likely to be, so likely keys can grow their touch area. Off in
    /// fields without suggestions (passwords, URLs), inside a word, and in Justin mode.
    private func buildLetterPrior() -> LetterPrior? {
        guard settings.smartHitTargets, suggestionsAllowed, state.layer == .letters, !justinModeActive,
              let engine, engine.language == language, !cursorIsInsideWord else { return nil }
        return engine.predictor.letterPrior(prefix: composingWord, previous: previousWord)
    }

    private func computedShift(current: ShiftState) -> ShiftState {
        if current == .locked { return .locked }
        if shiftTouchedManually { return current }
        guard state.layer == .letters else { return current }
        switch traits.autocapitalization {
        case .allCharacters: return .locked
        case .words: return composingWord.isEmpty ? .on : .off
        case .sentences: return settings.autoCapitalize && composingWord.isEmpty && isSentenceStart ? .on : .off
        default: return .off
        }
    }

    // MARK: Suggestions

    /// Everything the strip depends on, captured on the main thread so the search can run on
    /// the suggestion queue without touching mutable state. The engine's parts are read-only or
    /// lock-protected; the key-map-bound autocorrect is fetched here so its cache stays main-only.
    /// The engine is held weakly: a language switch drops it, and a queued search must not keep
    /// a second lexicon alive in the extension's tight memory budget – it simply finds nothing.
    private struct SuggestionInput {
        var composing: String
        var previous: String?
        var isSentenceStart: Bool
        var lastCommit: Commit?
        weak var engine: KeyboardEngine?
        weak var autocorrect: Autocorrect?
        var allowed: Bool
        var autocorrectAllowed: Bool
        var predictions: Bool
        var justinMode: Bool
    }

    private func suggestionInput(layer: KeyboardLayer) -> SuggestionInput {
        let engine = suggestionsAllowed && layer == .letters && self.engine?.language == language ? self.engine : nil
        let justin = justinModeActive
        let composing = engine == nil ? "" : composingWord
        // Only the correction search needs context; skip the reads when nothing will run.
        let needsContext = engine != nil && !justin
        return SuggestionInput(
            composing: composing,
            previous: needsContext ? previousWord : nil,
            isSentenceStart: needsContext ? isSentenceStart : false,
            lastCommit: lastCommit,
            engine: engine,
            autocorrect: needsContext && !composing.isEmpty ? keyMap.flatMap { engine?.autocorrect(for: $0) } : nil,
            allowed: suggestionsAllowed && layer == .letters,
            autocorrectAllowed: autocorrectAllowed,
            predictions: settings.predictions,
            justinMode: justin)
    }

    private static func buildSuggestions(_ input: SuggestionInput) -> [Suggestion] {
        guard input.allowed, let engine = input.engine else { return [] }
        let composing = input.composing
        if input.justinMode {
            return [Suggestion(text: justin(matching: composing), kind: composing.isEmpty ? .prediction : .primary)]
        }
        if composing.isEmpty {
            if case .swipe(let word, let alternates, _) = input.lastCommit {
                var items = [Suggestion(text: word, kind: .primary)]
                for alt in alternates.prefix(2) { items.insert(Suggestion(text: alt, kind: .alternate), at: items.count == 1 ? 0 : items.count) }
                return items
            }
            guard input.predictions else { return [] }
            return engine.predictor.nextWords(after: input.previous, isSentenceStart: input.isSentenceStart).map { Suggestion(text: $0, kind: .prediction) }
        }

        guard let autocorrect = input.autocorrect else { return [] }
        let previous = input.previous
        let start = input.isSentenceStart
        let corrections = autocorrect.corrections(for: composing, previousWord: previous, isSentenceStart: start)
        let completions = input.predictions ? engine.predictor.completions(prefix: composing, previous: previous, isSentenceStart: start, limit: 4) : []
        let best = corrections.first
        let willReplace = input.autocorrectAllowed && best?.autoApply == true && best?.word != composing
        // A capital the user typed (or auto-capitalisation produced) stays: "Hakko" → "Hallo", not "hallo".
        let keepCapital = composing.first?.isUppercase == true
        func cased(_ w: String) -> String {
            keepCapital && w.first?.isLowercase == true ? w.prefix(1).uppercased() + w.dropFirst() : w
        }
        let primary = willReplace ? cased(best!.word) : composing

        var pool: [String] = []
        for c in corrections where c.word.lowercased() != primary.lowercased() { pool.append(cased(c.word)) }
        for c in completions where c.lowercased() != primary.lowercased() && !pool.contains(where: { $0.lowercased() == c.lowercased() }) { pool.append(c) }
        // Prefer a completion in the first alternate slot when the typed prefix is a real word start.
        if let firstCompletion = completions.first(where: { $0.lowercased() != primary.lowercased() }), let i = pool.firstIndex(of: firstCompletion), i > 0 {
            pool.remove(at: i); pool.insert(firstCompletion, at: 0)
        }
        var items: [Suggestion] = []
        if willReplace {
            items.append(Suggestion(text: composing, kind: .literal))
        } else if let first = pool.first {
            items.append(Suggestion(text: first, kind: .alternate)); pool.removeFirst()
        }
        items.append(Suggestion(text: primary, kind: .primary))
        if let next = pool.first { items.append(Suggestion(text: next, kind: .alternate)) }
        return items
    }

    // MARK: Key events

    /// `touch` is where the finger landed on the key grid (grid coordinates); it feeds the tap map.
    func handle(key: Key, touch: CGPoint? = nil) {
        currentTouch = touch
        defer { currentTouch = nil }
        perform(key.action, from: key)
    }

    /// Runs the key's hold action (e.g. emoji on the comma key); keys without one are ignored.
    func handleLongPress(key: Key) {
        guard let action = key.longPressAction else { return }
        perform(action, from: key)
    }

    private func perform(_ action: KeyAction, from key: Key) {
        switch action {
        case .character(let text):
            insertCharacter(text, fromKey: key)
        case .space:
            handleSpace()
        case .backspace:
            handleBackspace()
        case .shift:
            toggleShift()
        case .newline:
            commitComposingIfNeeded(trigger: "\n")
            insertText("\n")
            afterEdit(lastWasSpace: false)
        case .switchLayer(let layer):
            var s = state
            s.layer = layer
            if layer != .letters { s.shift = .off }
            shiftTouchedManually = false
            state = s
            refreshNow()
        case .globe:
            delegate?.inputControllerRequestsGlobe(self)
        case .emoji:
            delegate?.inputControllerRequestsEmoji(self)
        case .dismiss:
            delegate?.inputControllerRequestsDismiss(self)
        }
    }

    private func insertCharacter(_ raw: String, fromKey key: Key) {
        var text = raw
        if key.isLetter, state.shift.isActive { text = text.uppercased() }
        let isPunctuation = text.count == 1 && (Self.sentenceTerminators.contains(text.first!) || ",;:".contains(text))

        if isPunctuation {
            if autoSpacePending, textBefore.hasSuffix(" ") {
                deleteBackwardOnce()               // "wort ." → "wort."
                insertText(text)
                insertText(" ")
                lastCommit = nil
                afterEdit(lastWasSpace: false)
                return
            }
            commitComposingIfNeeded(trigger: text)
            insertText(text)
            afterEdit(lastWasSpace: false)
            return
        }

        if key.isLetter || !key.isFunction {
            // Typing right after a swipe word continues with a new word; the auto-space stays.
            if case .swipe = lastCommit { lastCommit = nil }
            autoSpacePending = false
        }
        recordTap(text, touch: currentTouch)
        insertText(text)
        afterEdit(lastWasSpace: false, consumedShift: key.isLetter)
    }

    /// Appends the tap behind `text`, which is about to join the composing word. A buffer that has
    /// drifted from the word (typing started before we were watching) is dropped, never patched.
    private func recordTap(_ text: String, touch: CGPoint?) {
        if wordTaps.count != composingWord.count { wordTaps.removeAll() }
        let point = text.count == 1 ? (touch ?? Self.unknownTap) : Self.unknownTap
        for c in text { wordTaps.append((c, point)) }
    }

    private func handleSpace() {
        if autoSpacePending, textBefore.hasSuffix(" ") {
            // Space right after a swipe: the space is already there.
            autoSpacePending = false
            lastCommit = nil
            lastKeyWasSpace = true
            afterEdit(lastWasSpace: true)
            return
        }
        autoSpacePending = false
        let before = textBefore
        if settings.doubleSpacePeriod, lastKeyWasSpace, before.hasSuffix(" "), before.count >= 2 {
            let prev = before[before.index(before.endIndex, offsetBy: -2)]
            if prev.isLetter || prev.isNumber || ")\"“”".contains(prev) {
                deleteBackwardOnce()
                insertText(". ")
                lastCommit = nil
                afterEdit(lastWasSpace: false)
                return
            }
        }
        commitComposingIfNeeded(trigger: " ")
        insertText(" ")
        afterEdit(lastWasSpace: true)
    }

    private func handleBackspace() {
        switch lastCommit {
        case .swipe(let word, _, let autoSpace):
            let expected = word + (autoSpace ? " " : "")
            if textBefore.hasSuffix(expected) {
                delete(count: expected.count)
                lastCommit = nil
                autoSpacePending = false
                afterEdit(lastWasSpace: false)
                return
            }
        case .autocorrect(let original, let corrected, let trigger):
            if textBefore.hasSuffix(corrected + trigger) {
                delete(count: corrected.count + trigger.count)
                insertText(original)
                engine?.user.rejectCorrection(typed: original)
                // The correction was wrong, so what it taught the tap map was wrong too.
                if canUndoTapLearning { tapMap?.undoLastLearning(); canUndoTapLearning = false }
                lastCommit = nil
                afterEdit(lastWasSpace: false)
                return
            }
        default:
            break
        }
        lastCommit = nil
        autoSpacePending = false
        deleteBackwardOnce()
        afterEdit(lastWasSpace: false)
    }

    func backspaceRepeat(wordwise: Bool) {
        lastCommit = nil
        autoSpacePending = false
        if wordwise {
            let before = textBefore
            var n = 0
            var idx = before.endIndex
            while idx > before.startIndex, before[before.index(before: idx)] == " " { idx = before.index(before: idx); n += 1 }
            while idx > before.startIndex, before[before.index(before: idx)] != " ", before[before.index(before: idx)] != "\n" { idx = before.index(before: idx); n += 1 }
            delete(count: max(1, n))
        } else {
            deleteBackwardOnce()
        }
        afterEdit(lastWasSpace: false)
    }

    private func toggleShift() {
        var s = state
        switch s.shift {
        case .off: s.shift = .on
        case .on, .locked: s.shift = .off
        }
        shiftTouchedManually = true
        state = s
    }

    func lockShift() {
        var s = state
        s.shift = .locked
        shiftTouchedManually = true
        state = s
    }

    func shiftSlide(to key: Key) {
        guard let c = key.character else { return }
        if case .swipe = lastCommit { lastCommit = nil }
        autoSpacePending = false
        recordTap(String(c).uppercased(), touch: nil)
        insertText(String(c).uppercased())
        afterEdit(lastWasSpace: false, consumedShift: true)
    }

    func insertAlternate(_ text: String, for key: Key) {
        if case .swipe = lastCommit { lastCommit = nil }
        autoSpacePending = false
        recordTap(text, touch: nil)
        insertText(text)
        afterEdit(lastWasSpace: false, consumedShift: key.isLetter)
    }

    func moveCursor(by offset: Int) {
        edit({ c in
            if offset > 0 {
                let n = min(offset, c.after.count)
                return DocumentContext(before: c.before + c.after.prefix(n), after: String(c.after.dropFirst(n)))
            }
            let n = min(-offset, c.before.count)
            return DocumentContext(before: String(c.before.dropLast(n)), after: c.before.suffix(n) + c.after)
        }) { proxy.moveCursor(by: offset) }
        lastCommit = nil
        autoSpacePending = false
        wordTaps.removeAll()
        refreshNow()
    }

    // MARK: Edits from outside the key grid (emoji panel)

    /// Inserts text the emoji panel picked; the UI state follows.
    func insertFromPanel(_ text: String) {
        lastCommit = nil
        autoSpacePending = false
        insertText(text)
        afterEdit(lastWasSpace: false)
    }

    func deleteBackwardFromPanel() {
        lastCommit = nil
        autoSpacePending = false
        deleteBackwardOnce()
        afterEdit(lastWasSpace: false)
    }

    // MARK: Swipe

    func handleSwipe(path: [CGPoint], keyMap: KeyMap, fallbackKey: Key?) {
        guard traits.allowsSwipe, settings.swipeTyping, let engine, engine.language == language else {
            if let fallbackKey { handle(key: fallbackKey) }
            return
        }
        if cursorIsInsideWord {
            if let fallbackKey { handle(key: fallbackKey) }
            return
        }
        // A half-typed word is finished (and autocorrected) like a space would do.
        if !composingWord.isEmpty { commitComposingIfNeeded(trigger: " ") }
        let composing = composingWord
        let previous = composing.isEmpty ? previousWord : composing
        let candidates = engine.decodeSwipe(path: path, keyMap: keyMap, previousWord: previous, limit: 4)
        guard let best = candidates.first else {
            if let fallbackKey { handle(key: fallbackKey) }
            return
        }
        // Separate from a partially typed word or the previous word with a space.
        let before = textBefore
        if let last = before.last, !last.isWhitespace, !last.isNewline, !autoSpacePending, !Self.openingDelimiters.contains(last) {
            insertText(" ")
        }
        let cased = justinModeActive ? applyCase(to: Self.justinWord) : applyCase(to: best.word)
        insertText(cased + " ")
        let alternates = justinModeActive ? [] : candidates.dropFirst().map { applyCase(to: $0.word) }
        lastCommit = .swipe(word: cased, alternates: Array(alternates), autoSpace: true)
        autoSpacePending = true
        learn(word: cased, after: previous)
        afterEdit(lastWasSpace: true, consumedShift: true)
    }

    /// Applies shift / sentence casing to a dictionary word without lowercasing German nouns.
    private func applyCase(to word: String) -> String {
        switch state.shift {
        case .locked: return word.uppercased()
        case .on: return word.prefix(1).uppercased() + word.dropFirst()
        case .off:
            if isSentenceStart && settings.autoCapitalize { return word.prefix(1).uppercased() + word.dropFirst() }
            return word
        }
    }

    // MARK: Suggestions tapped

    func accept(_ suggestion: Suggestion) {
        let composing = composingWord
        let previous = previousWord
        if justinModeActive {
            if composing.isEmpty, case .swipe = lastCommit { return }   // already „Justin“
            if !composing.isEmpty { delete(count: composing.count) }
            insertText(Self.justin(matching: composing) + " ")
            lastCommit = .suggestion(word: Self.justinWord)
            autoSpacePending = true
            afterEdit(lastWasSpace: true, consumedShift: true)
            return
        }
        switch (suggestion.kind, lastCommit) {
        case (_, .swipe(let word, _, let autoSpace)) where composing.isEmpty:
            let expected = word + (autoSpace ? " " : "")
            if textBefore.hasSuffix(expected) { delete(count: expected.count) }
            insertText(suggestion.text + " ")
            var alts = [word]
            if case .swipe(_, let a, _) = lastCommit { alts += a.filter { $0 != suggestion.text } }
            lastCommit = .swipe(word: suggestion.text, alternates: Array(alts.prefix(3)), autoSpace: true)
            autoSpacePending = true
            learn(word: suggestion.text, after: previous)
        case (.prediction, _):
            if !composing.isEmpty { delete(count: composing.count) }
            insertText(suggestion.text + " ")
            lastCommit = .suggestion(word: suggestion.text)
            autoSpacePending = true
            learn(word: suggestion.text, after: previous)
        case (.literal, _):
            // The user insists on the typed word: every tap behind it was on target.
            learnTaps(typed: composing, committed: composing)
            insertText(" ")
            if settings.learnWords { engine?.user.add(word: composing) }
            lastCommit = nil
            autoSpacePending = true
        default:
            // A hand-picked correction is as good a teacher as an automatic one.
            learnTaps(typed: composing, committed: suggestion.text)
            if !composing.isEmpty { delete(count: composing.count) }
            insertText(suggestion.text + " ")
            lastCommit = .suggestion(word: suggestion.text)
            autoSpacePending = true
            learn(word: suggestion.text, after: previous)
        }
        afterEdit(lastWasSpace: true, consumedShift: true)
    }

    // MARK: Internals

    /// Applies autocorrect to the word before the cursor when a separator is typed.
    private func commitComposingIfNeeded(trigger: String) {
        let composing = composingWord
        guard !composing.isEmpty else { return }
        let previous = previousWord
        lastCommit = nil
        if justinModeActive {
            wordTaps.removeAll()
            let replacement = Self.justin(matching: composing)
            guard replacement != composing else { return }
            delete(count: composing.count)
            insertText(replacement)
            return
        }
        guard suggestionsAllowed, let keyMap, let engine, engine.language == language else { wordTaps.removeAll(); return }
        if autocorrectAllowed, trigger == " " || trigger == "\n" || Self.sentenceTerminators.contains(trigger.first!) || trigger == "," {
            let corrections = engine.autocorrect(for: keyMap).corrections(for: composing, previousWord: previous, isSentenceStart: isSentenceStart)
            if let best = corrections.first, best.autoApply, best.word != composing {
                var replacement = best.word
                // Keep a capital the user typed (or auto-capitalisation produced): "Hakko" → "Hallo".
                if composing.first?.isUppercase == true, replacement.first?.isLowercase == true {
                    replacement = replacement.prefix(1).uppercased() + replacement.dropFirst()
                }
#if DEBUG
                inputLog.debug("autocorrect \(composing, privacy: .public) -> \(replacement, privacy: .public) (\(corrections.prefix(3).map { "\($0.word)" }.joined(separator: ","), privacy: .public))")
#endif
                delete(count: composing.count)
                insertText(replacement)
                lastCommit = .autocorrect(original: composing, corrected: replacement, trigger: trigger)
                learn(word: replacement, after: previous)
                canUndoTapLearning = learnTaps(typed: composing, committed: replacement)
                return
            }
        }
        learn(word: composing, after: previous)
        learnTaps(typed: composing, committed: composing)
    }

    /// Feeds the taps behind a word that just left the composing state into the tap map. Only
    /// when the recorded taps spell exactly the typed word – a paste, a cursor jump into another
    /// word or typing that began before we watched leaves a buffer that is simply dropped (see
    /// `TapMap.samples` for what is learned from a correction). Returns whether the map changed.
    @discardableResult
    private func learnTaps(typed: String, committed: String) -> Bool {
        defer { wordTaps.removeAll() }
        canUndoTapLearning = false
        guard settings.adaptiveTapMap, suggestionsAllowed, !justinModeActive, let tapMap, let keyMap,
              wordTaps.count == typed.count, String(wordTaps.map(\.char)) == typed else { return false }
        let samples = TapMap.samples(taps: wordTaps.map(\.point), typed: typed, committed: committed, keyMap: keyMap)
        guard !samples.isEmpty else { return false }
        tapMap.learn(samples, keyMap: keyMap)
        return true
    }

    private func learn(word: String, after previous: String?) {
        guard settings.learnWords, suggestionsAllowed, !justinModeActive, let engine, engine.language == language else { return }
        engine.user.learn(word: word, after: previous)
    }

    private func delete(count: Int) {
        guard count > 0 else { return }
#if DEBUG
        inputLog.debug("delete \(count)")
#endif
        edit({ DocumentContext(before: String($0.before.dropLast(count)), after: $0.after) }) {
            for _ in 0..<count { proxy.deleteBackward() }
        }
    }

    private func afterEdit(lastWasSpace: Bool, consumedShift: Bool = false) {
        lastKeyWasSpace = lastWasSpace
        // Backspace shortens the word; its taps follow (the deleted tap taught nothing).
        let composingCount = composingWord.count
        if wordTaps.count > composingCount { wordTaps.removeLast(wordTaps.count - composingCount) }
        var s = state
        if consumedShift, s.shift == .on { s.shift = .off }
        state = s
        // Typing a character ends a manual shift override; auto-capitalisation takes over again.
        if consumedShift { shiftTouchedManually = false }
        refreshNow()
    }
}
