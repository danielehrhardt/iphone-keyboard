import UIKit
import KeyboardCore

/// Everything the keyboard shows besides the keys themselves.
struct InputUIState: Equatable {
    var layer: KeyboardLayer = .letters
    var shift: ShiftState = .off
    var suggestions: [Suggestion] = []
    /// Next-letter distribution for the key grid's dynamic hit targets; nil = plain hit test.
    var letterPrior: LetterPrior?
}

protocol InputControllerDelegate: AnyObject {
    func inputController(_ c: InputController, didUpdate state: InputUIState)
    func inputControllerRequestsGlobe(_ c: InputController)
    func inputControllerRequestsEmoji(_ c: InputController)
    func inputControllerRequestsDismiss(_ c: InputController)
}

/// The text-editing brain: turns key events into document edits, runs autocorrect on word
/// boundaries, commits swipe words, tracks shift state and produces the suggestion strip.
final class InputController {

    private enum Commit: Equatable {
        case swipe(word: String, alternates: [String], autoSpace: Bool)
        case autocorrect(original: String, corrected: String, trigger: String)
        case suggestion(word: String)
    }

    /// nil until the lexicon finished loading; typing works, suggestions/swipe wait for it.
    var engine: KeyboardEngine?
    let settings: KeyboardSettings
    let proxy: TextProxy
    weak var delegate: InputControllerDelegate?

    private(set) var state = InputUIState() { didSet { if state != oldValue { delegate?.inputController(self, didUpdate: state) } } }
    var traits = FieldTraits() { didSet { if traits != oldValue { fieldChanged() } } }
    var keyMap: KeyMap?

    private var lastCommit: Commit?
    private var autoSpacePending = false
    private var lastKeyWasSpace = false
    private var shiftTouchedManually = false

    init(engine: KeyboardEngine?, settings: KeyboardSettings, proxy: TextProxy) {
        self.engine = engine
        self.settings = settings
        self.proxy = proxy
    }

    // MARK: Context helpers

    private static let wordCharacters: (Character) -> Bool = { $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }
    private static let openingDelimiters: Set<Character> = GermanRules.openingDelimiters.union(["'", "/", "-", "#", "@"])

    /// The word being typed (letters immediately before the cursor).
    var composingWord: String {
        let before = proxy.textBefore
        var start = before.endIndex
        while start > before.startIndex {
            let c = before[before.index(before: start)]
            if !Self.wordCharacters(c) { break }
            start = before.index(before: start)
        }
        // Only when the cursor is at the end of the word.
        if let next = proxy.textAfter.first, Self.wordCharacters(next) { return "" }
        return String(before[start...])
    }

    /// The last complete word before the composing word.
    var previousWord: String? {
        if cursorIsInsideWord { return nil }
        let before = proxy.textBefore
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
        guard let next = proxy.textAfter.first, Self.wordCharacters(next) else { return false }
        return proxy.textBefore.last.map(Self.wordCharacters) ?? false
    }

    private var isSentenceStart: Bool {
        GermanRules.isSentenceStart(String(proxy.textBefore.dropLast(composingWord.count)))
    }

    private var suggestionsAllowed: Bool { traits.allowsSuggestions }
    private var autocorrectAllowed: Bool { settings.autocorrect && traits.allowsAutocorrect }
    /// „Justin-Modus“: every word becomes „Justin“ – in every field, regardless of the autocorrect
    /// toggle, with no literal, alternate or backspace escape.
    private var justinModeActive: Bool { settings.justinMode }

    static let justinWord = "Justin"

    /// „Justin“, or „JUSTIN“ when the typed word was written in all caps.
    private func justin(matching typed: String) -> String {
        let letters = typed.filter(\.isLetter)
        let allCaps = letters.count > 1 && letters.allSatisfy(\.isUppercase)
        return allCaps ? Self.justinWord.uppercased() : Self.justinWord
    }

    // MARK: Field / external changes

    private func fieldChanged() {
        lastCommit = nil
        autoSpacePending = false
        shiftTouchedManually = false
        var s = state
        s.layer = initialLayer()
        state = s
        refresh()
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

    /// Called when the host text changed for reasons other than our own edits (cursor moves, pastes…).
    func textDidChangeExternally() {
        if case .swipe(let w, _, let autoSpace) = lastCommit {
            let expected = w + (autoSpace ? " " : "")
            if !proxy.textBefore.hasSuffix(expected) { lastCommit = nil; autoSpacePending = false }
        } else if case .autocorrect(_, let corrected, let trigger) = lastCommit, !proxy.textBefore.hasSuffix(corrected + trigger) {
            lastCommit = nil
        }
        if autoSpacePending, !proxy.textBefore.hasSuffix(" ") { autoSpacePending = false }
        refresh()
    }

    /// Recomputes shift and suggestions from the document.
    func refresh() {
        var s = state
        s.shift = computedShift(current: s.shift)
        s.suggestions = buildSuggestions()
        s.letterPrior = buildLetterPrior()
        state = s
    }

    /// What the next letter is likely to be, so likely keys can grow their touch area. Off in
    /// fields without suggestions (passwords, URLs), inside a word, and in Justin mode.
    private func buildLetterPrior() -> LetterPrior? {
        guard settings.smartHitTargets, suggestionsAllowed, state.layer == .letters, !justinModeActive,
              let engine, !cursorIsInsideWord else { return nil }
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

    private func buildSuggestions() -> [Suggestion] {
        guard suggestionsAllowed, state.layer == .letters, let engine else { return [] }
        let composing = composingWord
        if justinModeActive {
            return [Suggestion(text: justin(matching: composing), kind: composing.isEmpty ? .prediction : .primary)]
        }
        if composing.isEmpty {
            if case .swipe(let word, let alternates, _) = lastCommit {
                var items = [Suggestion(text: word, kind: .primary)]
                for alt in alternates.prefix(2) { items.insert(Suggestion(text: alt, kind: .alternate), at: items.count == 1 ? 0 : items.count) }
                return items
            }
            guard settings.predictions else { return [] }
            return engine.predictor.nextWords(after: previousWord, isSentenceStart: isSentenceStart).map { Suggestion(text: $0, kind: .prediction) }
        }

        guard let keyMap else { return [] }
        let previous = previousWord
        let start = isSentenceStart
        let corrections = engine.autocorrect(for: keyMap).corrections(for: composing, previousWord: previous, isSentenceStart: start)
        let completions = settings.predictions ? engine.predictor.completions(prefix: composing, previous: previous, isSentenceStart: start, limit: 4) : []
        let best = corrections.first
        let willReplace = autocorrectAllowed && best?.autoApply == true && best?.word != composing
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

    func handle(key: Key) { perform(key.action, from: key) }

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
            proxy.insert("\n")
            afterEdit(lastWasSpace: false)
        case .switchLayer(let layer):
            var s = state
            s.layer = layer
            if layer != .letters { s.shift = .off }
            shiftTouchedManually = false
            state = s
            refresh()
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
        let isPunctuation = text.count == 1 && (GermanRules.sentenceTerminators.contains(text.first!) || ",;:".contains(text))

        if isPunctuation {
            if autoSpacePending, proxy.textBefore.hasSuffix(" ") {
                proxy.deleteBackward()             // "wort ." → "wort."
                proxy.insert(text)
                proxy.insert(" ")
                lastCommit = nil
                afterEdit(lastWasSpace: false)
                return
            }
            commitComposingIfNeeded(trigger: text)
            proxy.insert(text)
            afterEdit(lastWasSpace: false)
            return
        }

        if key.isLetter || !key.isFunction {
            // Typing right after a swipe word continues with a new word; the auto-space stays.
            if case .swipe = lastCommit { lastCommit = nil }
            autoSpacePending = false
        }
        proxy.insert(text)
        afterEdit(lastWasSpace: false, consumedShift: key.isLetter)
    }

    private func handleSpace() {
        if autoSpacePending, proxy.textBefore.hasSuffix(" ") {
            // Space right after a swipe: the space is already there.
            autoSpacePending = false
            lastCommit = nil
            lastKeyWasSpace = true
            afterEdit(lastWasSpace: true)
            return
        }
        autoSpacePending = false
        let before = proxy.textBefore
        if settings.doubleSpacePeriod, lastKeyWasSpace, before.hasSuffix(" "), before.count >= 2 {
            let prev = before[before.index(before.endIndex, offsetBy: -2)]
            if prev.isLetter || prev.isNumber || ")\"“”".contains(prev) {
                proxy.deleteBackward()
                proxy.insert(". ")
                lastCommit = nil
                afterEdit(lastWasSpace: false)
                return
            }
        }
        commitComposingIfNeeded(trigger: " ")
        proxy.insert(" ")
        afterEdit(lastWasSpace: true)
    }

    private func handleBackspace() {
        switch lastCommit {
        case .swipe(let word, _, let autoSpace):
            let expected = word + (autoSpace ? " " : "")
            if proxy.textBefore.hasSuffix(expected) {
                delete(count: expected.count)
                lastCommit = nil
                autoSpacePending = false
                afterEdit(lastWasSpace: false)
                return
            }
        case .autocorrect(let original, let corrected, let trigger):
            if proxy.textBefore.hasSuffix(corrected + trigger) {
                delete(count: corrected.count + trigger.count)
                proxy.insert(original)
                engine?.user.rejectCorrection(typed: original)
                lastCommit = nil
                afterEdit(lastWasSpace: false)
                return
            }
        default:
            break
        }
        lastCommit = nil
        autoSpacePending = false
        proxy.deleteBackward()
        afterEdit(lastWasSpace: false)
    }

    func backspaceRepeat(wordwise: Bool) {
        lastCommit = nil
        autoSpacePending = false
        if wordwise {
            let before = proxy.textBefore
            var n = 0
            var idx = before.endIndex
            while idx > before.startIndex, before[before.index(before: idx)] == " " { idx = before.index(before: idx); n += 1 }
            while idx > before.startIndex, before[before.index(before: idx)] != " ", before[before.index(before: idx)] != "\n" { idx = before.index(before: idx); n += 1 }
            delete(count: max(1, n))
        } else {
            proxy.deleteBackward()
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
        proxy.insert(String(c).uppercased())
        afterEdit(lastWasSpace: false, consumedShift: true)
    }

    func insertAlternate(_ text: String, for key: Key) {
        if case .swipe = lastCommit { lastCommit = nil }
        autoSpacePending = false
        proxy.insert(text)
        afterEdit(lastWasSpace: false, consumedShift: key.isLetter)
    }

    func moveCursor(by offset: Int) {
        proxy.moveCursor(by: offset)
        lastCommit = nil
        autoSpacePending = false
        refresh()
    }

    // MARK: Swipe

    func handleSwipe(path: [CGPoint], keyMap: KeyMap, fallbackKey: Key?) {
        guard traits.allowsSwipe, settings.swipeTyping, let engine else {
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
        let before = proxy.textBefore
        if let last = before.last, !last.isWhitespace, !last.isNewline, !autoSpacePending, !Self.openingDelimiters.contains(last) {
            proxy.insert(" ")
        }
        let cased = justinModeActive ? applyCase(to: Self.justinWord) : applyCase(to: best.word)
        proxy.insert(cased + " ")
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
            proxy.insert(justin(matching: composing) + " ")
            lastCommit = .suggestion(word: Self.justinWord)
            autoSpacePending = true
            afterEdit(lastWasSpace: true, consumedShift: true)
            return
        }
        switch (suggestion.kind, lastCommit) {
        case (_, .swipe(let word, _, let autoSpace)) where composing.isEmpty:
            let expected = word + (autoSpace ? " " : "")
            if proxy.textBefore.hasSuffix(expected) { delete(count: expected.count) }
            proxy.insert(suggestion.text + " ")
            var alts = [word]
            if case .swipe(_, let a, _) = lastCommit { alts += a.filter { $0 != suggestion.text } }
            lastCommit = .swipe(word: suggestion.text, alternates: Array(alts.prefix(3)), autoSpace: true)
            autoSpacePending = true
            learn(word: suggestion.text, after: previous)
        case (.prediction, _):
            if !composing.isEmpty { delete(count: composing.count) }
            proxy.insert(suggestion.text + " ")
            lastCommit = .suggestion(word: suggestion.text)
            autoSpacePending = true
            learn(word: suggestion.text, after: previous)
        case (.literal, _):
            proxy.insert(" ")
            if settings.learnWords { engine?.user.add(word: composing) }
            lastCommit = nil
            autoSpacePending = true
        default:
            if !composing.isEmpty { delete(count: composing.count) }
            proxy.insert(suggestion.text + " ")
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
            let replacement = justin(matching: composing)
            guard replacement != composing else { return }
            delete(count: composing.count)
            proxy.insert(replacement)
            return
        }
        guard suggestionsAllowed, let keyMap, let engine else { return }
        if autocorrectAllowed, trigger == " " || trigger == "\n" || GermanRules.sentenceTerminators.contains(trigger.first!) || trigger == "," {
            let corrections = engine.autocorrect(for: keyMap).corrections(for: composing, previousWord: previous, isSentenceStart: isSentenceStart)
            if let best = corrections.first, best.autoApply, best.word != composing {
                var replacement = best.word
                // Keep a capital the user typed (or auto-capitalisation produced): "Hakko" → "Hallo".
                if composing.first?.isUppercase == true, replacement.first?.isLowercase == true {
                    replacement = replacement.prefix(1).uppercased() + replacement.dropFirst()
                }
                delete(count: composing.count)
                proxy.insert(replacement)
                lastCommit = .autocorrect(original: composing, corrected: replacement, trigger: trigger)
                learn(word: replacement, after: previous)
                return
            }
        }
        learn(word: composing, after: previous)
    }

    private func learn(word: String, after previous: String?) {
        guard settings.learnWords, suggestionsAllowed, !justinModeActive else { return }
        engine?.user.learn(word: word, after: previous)
    }

    private func delete(count: Int) {
        for _ in 0..<count { proxy.deleteBackward() }
    }

    private func afterEdit(lastWasSpace: Bool, consumedShift: Bool = false) {
        lastKeyWasSpace = lastWasSpace
        var s = state
        if consumedShift, s.shift == .on { s.shift = .off }
        state = s
        // Typing a character ends a manual shift override; auto-capitalisation takes over again.
        if consumedShift { shiftTouchedManually = false }
        refresh()
    }
}
