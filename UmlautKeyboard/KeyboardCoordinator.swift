import UIKit
import KeyboardCore

/// Glues `KeyboardView`, `InputController` and the engine together. Used by the extension's
/// `KeyboardViewController` and by the host app's in-app demo keyboard, so both behave identically.
final class KeyboardCoordinator: NSObject {

    let settings: KeyboardSettings
    let feedback: Feedback
    let view: KeyboardView
    let input: InputController
    /// Copied text and images, shared with the app.
    let clipboard: ClipboardMonitor
    /// Whether the pasteboard may be read: the extension needs "Full Access", the app always has it.
    var hasFullAccess = true
    /// The AI features: model/key lookup and the requests behind the panel and the strip.
    let ai: AIAssistant
    /// What the panel's current request works on, captured when the panel opened.
    private var aiSource: AISource?
    /// The last text the assistant put into the document, for "Rückgängig".
    private var lastAIApplication: (inserted: String, original: String)?

    private struct AISource {
        let text: String
        let isSelection: Bool
    }
    private let thumbnails = NSCache<NSUUID, UIImage>()

    /// Hooks the owner provides (extension: system APIs; in-app demo: no-ops).
    var onGlobe: (() -> Void)?
    /// Raw touch events from the globe key (extension wires this to `handleInputModeList`).
    var onGlobeEvent: ((UIView, UIEvent?) -> Void)?
    var onDismiss: (() -> Void)?
    /// The gear in the period key's hold bubble was picked: open the app's settings.
    var onOpenSettings: (() -> Void)?
    /// Asked for the engine of a language whenever the keyboard switches to it (the extension
    /// loads lexicons lazily and keeps only the active one; the demo keyboard caches them).
    /// Called back on the main queue, with nil when the lexicon is missing.
    var engineProvider: ((KeyboardLanguage, @escaping (KeyboardEngine?) -> Void) -> Void)?
    var needsGlobeKey = false { didSet { if needsGlobeKey != oldValue { refreshLayoutOptions() } } }
    var isPhoneIdiom = true

    /// The language being typed; persisted so the next keyboard session continues in it.
    private(set) var language: KeyboardLanguage
    private(set) var currentLayer: KeyboardLayer = .letters
    private var layoutOptions = LayoutOptions()
    private var lastGridSize: CGSize = .zero
    private var lastGridLayer: KeyboardLayer?
    private var lastOptions: LayoutOptions?
    private var lastMetrics: KeyboardGeometry.Metrics?
    private var screenSize: CGSize = .zero
    private var traits: UITraitCollection

    init(settings: KeyboardSettings, proxy: TextProxy, engine: KeyboardEngine?, traits: UITraitCollection, tapMap: TapMap? = .standard,
         clipboard: ClipboardMonitor? = nil) {
        self.settings = settings
        self.traits = traits
        self.clipboard = clipboard ?? ClipboardMonitor(history: .shared(appGroup: KeyboardSettings.appGroup), settings: settings)
        language = settings.currentLanguage
        feedback = Feedback(settings: settings)
        ai = AIAssistant(settings: settings)
        let theme = KeyboardTheme.current(traits: traits, settings: settings)
        view = KeyboardView(theme: theme, feedback: feedback)
        // An engine for another language is of no use; wait for the provider instead.
        input = InputController(engine: engine?.language == language ? engine : nil, settings: settings, proxy: proxy, tapMap: tapMap)
        input.language = language
        // The suggestion strip is computed off the main thread; a tap returns as soon as the
        // character is in the document and the next touch is never queued behind a dictionary
        // search. One step below the main thread's QoS, so the search never outranks touches.
        input.suggestionQueue = DispatchQueue(label: "de.codext.umlaut.suggestions", qos: .userInitiated)
        super.init()
        input.delegate = self
        view.grid.delegate = self
        view.emojiDelegate = self
        view.clipboardDelegate = self
        view.suggestionBar.onActions = { [weak self] in
            guard let self else { return }
            self.feedback.functionTap()
            self.toggleActionMenu()
        }
        view.suggestionBar.onSelect = { [weak self] s in self?.input.accept(s) }
        view.suggestionBar.onDismiss = { [weak self] in
            guard let self else { return }
            self.feedback.keyTap()
            self.onDismiss?()
        }
        view.suggestionBar.onLanguage = { [weak self] in
            guard let self else { return }
            self.feedback.functionTap()
            self.switchToNextLanguage()
        }
        view.suggestionBar.language = settings.hasMultipleLanguages ? language : nil
        view.aiDelegate = self
        view.suggestionBar.showsAI = settings.aiEnabled
        view.suggestionBar.onAI = { [weak self] in
            guard let self else { return }
            self.feedback.functionTap()
            self.showAIPanel()
        }
        input.onSentenceCompleted = { [weak self] sentence in self?.sentenceCompleted(sentence) }
        input.onWordBoundary = { [weak self] text in self?.wordBoundary(text) }
        input.onTyping = { [weak self] in self?.ai.cancelContinuations() }
        view.onLayout = { [weak self] in self?.rebuildGridIfNeeded() }
    }

    // MARK: Environment

    var engine: KeyboardEngine? {
        get { input.engine }
        set {
            // A late-arriving engine for a language we have since left is dropped.
            guard newValue == nil || newValue?.language == language else { return }
            input.engine = newValue
            input.refresh()
        }
    }

    /// Picks up personal-dictionary changes made by the other process (app ↔ extension) and
    /// language settings changed in the app.
    func willAppear() {
        input.engine?.user.reloadIfChanged()
        input.tapMap?.reloadIfChanged()
        input.forgetDocument()
        // The app may have switched the current language off meanwhile.
        select(language: settings.currentLanguage)
        view.isActionMenuVisible = false
        if !settings.clipboardHistory, view.isClipboardVisible { view.isClipboardVisible = false }
        pasteboardMayHaveChanged()
        // Keys and models may have changed in the app.
        ai.reload()
        view.suggestionBar.showsAI = settings.aiEnabled
        if !settings.aiEnabled, view.isAIVisible { view.isAIVisible = false }
        if view.isAIVisible { view.aiPanel?.canUndo = canUndoAI }
    }

    // MARK: AI

    /// Opens the panel on the selection, or the text before the cursor.
    func showAIPanel() {
        view.grid.cancelAllTouches()
        view.isAIVisible = true
        guard let panel = view.aiPanel else { return }
        aiSource = currentAISource()
        panel.open(source: aiSource?.text, isSelection: aiSource?.isSelection ?? false,
                   tone: settings.aiRewriteTone, target: settings.aiTranslationTarget)
        panel.modelTitle = settings.aiDefaultModel?.title
        panel.canUndo = canUndoAI
        if let error = aiSetupError() { panel.set(phase: .failed(error)) }
    }

    /// Whatever keeps every feature from running, checked up front so the panel says so at once.
    private func aiSetupError() -> AIError? {
        guard settings.aiEnabled else { return .disabled }
        guard hasFullAccess else { return .needsFullAccess }
        guard let model = settings.aiDefaultModel else { return .noModel }
        guard ai.keys.hasKey(for: model.provider) else { return .missingKey(model.provider) }
        return nil
    }

    private func currentAISource() -> AISource? {
        if let selected = input.selectedText, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AISource(text: selected, isSelection: true)
        }
        let before = AIText.source(before: input.textBeforeCursor)
        return before.isEmpty ? nil : AISource(text: before, isSelection: false)
    }

    private var canUndoAI: Bool {
        guard let last = lastAIApplication else { return false }
        return input.textBeforeCursor.hasSuffix(last.inserted)
    }

    /// A sentence was finished: have it checked quietly; a correction shows up in the strip.
    private func sentenceCompleted(_ sentence: String) {
        guard settings.aiEnabled, settings.aiAutocorrect, hasFullAccess, input.traits.allowsSuggestions else { return }
        ai.checkSentence(sentence, language: language) { [weak self] corrected in
            guard let self, let corrected else { return }
            self.input.aiSentence = (sentence, corrected)
        }
    }

    /// The cursor rests after a space: after a short pause, ask for continuations.
    private func wordBoundary(_ text: String) {
        guard settings.aiEnabled, settings.aiSuggestions, hasFullAccess, input.traits.allowsSuggestions else { return }
        ai.continuations(after: text, language: language) { [weak self] items in
            guard let self, !items.isEmpty else { return }
            self.input.aiContinuations = (text, items)
        }
    }

    /// The host reported an edit (or the keyboard appeared): a copy may have happened meanwhile.
    /// Cheap unless the pasteboard's change count moved; at most one check every two seconds.
    func pasteboardMayHaveChanged() {
        guard hasFullAccess, settings.clipboardHistory else { return }
        clipboard.prune()
        if clipboard.captureIfChanged(minimumInterval: 2) != nil || view.isClipboardVisible {
            refreshClipboardPanel()
        }
    }

    // MARK: Actions

    /// The rows of the "⋯" menu for the current state.
    var availableActions: [KeyboardAction] {
        var actions: [KeyboardAction] = []
        if settings.clipboardHistory {
            actions.append(KeyboardAction(kind: .clipboard, title: "Zwischenablage", symbol: "doc.on.clipboard"))
        }
        actions.append(KeyboardAction(kind: .emoji, title: "Emoji", symbol: "face.smiling"))
        if settings.hasMultipleLanguages {
            let next = settings.nextLanguage(after: language)
            actions.append(KeyboardAction(kind: .language, title: "Sprache: \(next.title)", symbol: "globe"))
        }
        actions.append(KeyboardAction(kind: .dismiss, title: "Tastatur ausblenden", symbol: "keyboard.chevron.compact.down"))
        return actions
    }

    func toggleActionMenu() {
        if view.isActionMenuVisible {
            view.isActionMenuVisible = false
            return
        }
        view.grid.cancelAllTouches()
        view.isActionMenuVisible = true
        guard let menu = view.actionMenu else { return }
        menu.set(actions: availableActions)
        menu.onSelect = { [weak self] action in self?.perform(action) }
        menu.onClose = { [weak self] in self?.view.isActionMenuVisible = false }
    }

    func perform(_ action: KeyboardAction) {
        view.isActionMenuVisible = false
        feedback.keyTap()
        switch action.kind {
        case .clipboard: showClipboard()
        case .emoji: view.isEmojiVisible = true
        case .language: switchToNextLanguage()
        case .dismiss: onDismiss?()
        }
    }

    // MARK: Clipboard

    func showClipboard() {
        view.grid.cancelAllTouches()
        view.isClipboardVisible = true
        if hasFullAccess { clipboard.prune(); clipboard.captureIfChanged() }
        refreshClipboardPanel()
        view.clipboardPanel?.scrollToTop()
    }

    private func refreshClipboardPanel() {
        guard let panel = view.clipboardPanel, view.isClipboardVisible else { return }
        panel.thumbnailProvider = { [weak self] item in self?.thumbnail(for: item) }
        if !hasFullAccess {
            panel.notice = "Damit die Tastatur die Zwischenablage lesen kann, erlaube „Vollen Zugriff“ in den iOS-Einstellungen unter Tastaturen › Umlaut."
        } else if !settings.clipboardHistory {
            panel.notice = "Der Zwischenablage-Verlauf ist in den Einstellungen der Umlaut-App ausgeschaltet."
        } else {
            panel.notice = nil
        }
        panel.set(items: clipboard.history.items)
    }

    private func thumbnail(for item: ClipboardItem) -> UIImage? {
        let key = item.id as NSUUID
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let data = clipboard.history.thumbnailData(for: item), let image = UIImage(data: data) else { return nil }
        thumbnails.setObject(image, forKey: key)
        return image
    }

    // MARK: Languages

    /// Switches to the language after the current one (the suggestion strip's badge).
    func switchToNextLanguage() {
        select(language: settings.nextLanguage(after: language))
    }

    /// Makes `language` the typing language: layout, sentence rules, dictionary and personal
    /// dictionary follow. Typing keeps working while the engine loads.
    func select(language newLanguage: KeyboardLanguage) {
        let badge = settings.hasMultipleLanguages ? newLanguage : nil
        if view.suggestionBar.language != badge { view.suggestionBar.language = badge }
        guard newLanguage != language else {
            if input.engine == nil { requestEngine() }
            refreshLayoutOptions()
            return
        }
        language = newLanguage
        settings.currentLanguage = newLanguage
        view.grid.cancelAllTouches()
        input.language = newLanguage
        input.engine = nil
        input.refresh()
        refreshLayoutOptions()
        requestEngine()
    }

    private func requestEngine() {
        guard let engineProvider else { return }
        let wanted = language
        engineProvider(wanted) { [weak self] engine in
            guard let self, self.language == wanted, let engine, engine.language == wanted else { return }
            self.engine = engine
        }
    }

    /// Total keyboard height for the environment; also stores the sizes for later layout passes.
    @discardableResult
    func updateEnvironment(traits: UITraitCollection, screenSize: CGSize) -> CGFloat {
        self.traits = traits
        self.screenSize = screenSize
        isPhoneIdiom = traits.userInterfaceIdiom == .phone
        let h = KeyboardMetrics.heights(for: traits, screenSize: screenSize, keySize: settings.keySize)
        view.suggestionHeight = h.suggestions
        view.apply(theme: KeyboardTheme.current(traits: traits, settings: settings))
        refreshLayoutOptions()
        view.setNeedsLayout()     // metrics may have changed even when the options did not
        return h.keys + h.suggestions
    }

    func setFieldTraits(_ fieldTraits: FieldTraits) {
        input.traits = fieldTraits
        view.grid.returnLabel = fieldTraits.returnLabel
        view.grid.isReturnAccented = fieldTraits.returnIsAccented
        refreshLayoutOptions()
    }

    func themeChanged() {
        view.apply(theme: KeyboardTheme.current(traits: traits, settings: settings))
    }

    func cancelTouches() { view.grid.cancelAllTouches() }

    private func refreshLayoutOptions() {
        let options = LayoutOptions(needsGlobeKey: needsGlobeKey, showsEmojiKey: true,
                                    isEmailOrURL: input.traits.isEmailOrURL, showsCommaKey: settings.commaKey,
                                    emojiOnCommaKey: settings.emojiOnCommaKey,
                                    language: language, showsLanguageName: settings.hasMultipleLanguages,
                                    germanUmlautKeys: settings.germanUmlautKeys)
        // Called after every keystroke (the host reports each edit back); only a real change
        // is worth a layout pass.
        guard options != layoutOptions || lastOptions == nil else { return }
        layoutOptions = options
        view.setNeedsLayout()
    }

    private func rebuildGridIfNeeded() {
        let size = view.grid.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        if screenSize == .zero { screenSize = view.window?.windowScene?.screen.bounds.size ?? CGSize(width: size.width, height: size.width * 2) }
        let metrics = KeyboardMetrics.layoutMetrics(for: traits, screenSize: screenSize)
        if size != lastGridSize || lastGridLayer != currentLayer || lastOptions != layoutOptions || lastMetrics != metrics {
            lastGridSize = size; lastGridLayer = currentLayer; lastOptions = layoutOptions; lastMetrics = metrics
            let layout = KeyboardLayouts.layout(for: currentLayer, options: layoutOptions)
            view.grid.configure(layout: layout, metrics: metrics)
            input.keyMap = view.grid.keyMap
            input.refresh()     // the tap-map offsets depend on the key map
            view.grid.shiftState = input.state.shift
        }
    }
}

// MARK: - InputControllerDelegate

extension KeyboardCoordinator: InputControllerDelegate {
    func inputController(_ c: InputController, didUpdate state: InputUIState) {
        if state.layer != currentLayer {
            currentLayer = state.layer
            view.grid.cancelAllTouches()
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
        view.grid.shiftState = state.shift
        view.grid.letterPrior = state.letterPrior
        view.grid.tapOffsets = state.tapOffsets
        view.suggestionBar.set(state.suggestions)
        view.suggestionBar.aiButton.showsBadge = state.suggestions.contains { $0.kind == .ai }
    }

    func inputControllerRequestsGlobe(_ c: InputController) { onGlobe?() }
    func inputControllerRequestsEmoji(_ c: InputController) {
        // Reached from a hold on the comma key with the finger still down: the grid is about to be
        // hidden, so end its touches here rather than waiting for a lift it may never see.
        view.grid.cancelAllTouches()
        view.isActionMenuVisible = false
        view.isEmojiVisible = true
    }
    func inputControllerRequestsDismiss(_ c: InputController) { onDismiss?() }
}

// MARK: - KeyGridDelegate

extension KeyboardCoordinator: KeyGridDelegate {
    var swipeTypingEnabled: Bool { settings.swipeTyping && input.traits.allowsSwipe && input.engine != nil }
    var keyPreviewEnabled: Bool { settings.keyPreview && isPhoneIdiom }
    var swipeTrailEnabled: Bool { settings.swipeTrail }
    var longPressNumbersEnabled: Bool { settings.longPressNumbers }

    func keyGrid(_ grid: KeyGridView, didTap key: Key) { input.handle(key: key) }
    func keyGrid(_ grid: KeyGridView, didTap key: Key, at point: CGPoint) { input.handle(key: key, touch: point) }
    func keyGrid(_ grid: KeyGridView, didInsertAlternate text: String, for key: Key) { input.insertAlternate(text, for: key) }
    func keyGrid(_ grid: KeyGridView, didSwipe path: [CGPoint], keyMap: KeyMap) {
        let fallback = path.last.flatMap { grid.geometry?.keyFrame(at: $0)?.key }
        input.handleSwipe(path: path, keyMap: keyMap, fallbackKey: fallback)
    }
    /// Keys with a `longPressAction` (emoji on the comma key) perform it here and swallow the tap.
    /// Other keys without alternates (space, return …) do nothing; the touch stays pending and
    /// commits as a normal tap on release.
    func keyGrid(_ grid: KeyGridView, didLongPress key: Key) { input.handleLongPress(key: key) }
    func keyGrid(_ grid: KeyGridView, globeTouchEvent event: UIEvent?) { onGlobeEvent?(grid, event) }
    func keyGridBackspaceRepeat(_ grid: KeyGridView, wordwise: Bool) { input.backspaceRepeat(wordwise: wordwise) }
    func keyGrid(_ grid: KeyGridView, moveCursorBy offset: Int) { input.moveCursor(by: offset) }
    func keyGridDidDoubleTapShift(_ grid: KeyGridView) { input.lockShift() }
    func keyGrid(_ grid: KeyGridView, didShiftSlideTo key: Key) { input.shiftSlide(to: key) }
    func keyGridDidRequestSettings(_ grid: KeyGridView) { onOpenSettings?() }
}

// MARK: - EmojiPanelDelegate

extension KeyboardCoordinator: EmojiPanelDelegate {
    func emojiPanel(_ panel: EmojiPanelView, didPick emoji: String) {
        input.insertFromPanel(emoji)
        feedback.keyTap()
    }

    func emojiPanelDidTapBackspace(_ panel: EmojiPanelView) {
        input.deleteBackwardFromPanel()
        feedback.deleteTap()
    }

    func emojiPanelDidTapLetters(_ panel: EmojiPanelView) {
        view.isEmojiVisible = false
        input.refresh()
    }
}

// MARK: - ClipboardPanelDelegate

extension KeyboardCoordinator: ClipboardPanelDelegate {
    /// Text is typed into the document; an image goes back on the pasteboard, from where the
    /// system's Paste command inserts it (a keyboard cannot insert images itself).
    func clipboardPanel(_ panel: ClipboardPanelView, didPick item: ClipboardItem) {
        feedback.keyTap()
        switch item.kind {
        case .text:
            guard let text = item.text else { return }
            input.insertFromPanel(text)
            view.isClipboardVisible = false
            input.refresh()
        case .image:
            clipboard.copyToPasteboard(item)
            panel.showHint("Bild in die Zwischenablage gelegt – halte das Textfeld und wähle „Einfügen“.")
        }
    }

    func clipboardPanel(_ panel: ClipboardPanelView, didDelete item: ClipboardItem) {
        feedback.deleteTap()
        clipboard.history.remove(id: item.id)
        thumbnails.removeObject(forKey: item.id as NSUUID)
        refreshClipboardPanel()
    }

    func clipboardPanelDidTapClear(_ panel: ClipboardPanelView) {
        feedback.deleteTap()
        clipboard.history.removeAll()
        thumbnails.removeAllObjects()
        refreshClipboardPanel()
    }

    func clipboardPanelDidTapLetters(_ panel: ClipboardPanelView) {
        view.isClipboardVisible = false
        input.refresh()
    }
}

// MARK: - AIPanelDelegate

extension KeyboardCoordinator: AIPanelDelegate {
    func aiPanel(_ panel: AIPanelView, didRequest feature: AIFeature, tone: AIRewriteTone, target: AITranslationTarget) {
        settings.aiRewriteTone = tone
        settings.aiTranslationTarget = target
        panel.modelTitle = settings.aiModel(for: feature)?.title
        if let error = aiSetupError() { panel.set(phase: .failed(error)); return }
        aiSource = currentAISource()
        guard let source = aiSource else { panel.set(phase: .failed(.emptySource)); return }
        let spec = AIRequestSpec(feature: feature, text: source.text, language: language, tone: tone, target: target)
        panel.set(phase: .loading)
        view.suggestionBar.aiButton.isBusy = true
        ai.run(spec) { [weak self] result in
            guard let self else { return }
            self.view.suggestionBar.aiButton.isBusy = false
            guard self.view.isAIVisible, let panel = self.view.aiPanel, panel.feature == feature else { return }
            switch result {
            case .success(let items):
                panel.set(phase: .results(items))
                self.feedback.selectionTick()
            case .failure(let error):
                guard error != .cancelled else { return }
                panel.set(phase: .failed(error))
            }
        }
    }

    func aiPanel(_ panel: AIPanelView, didPick result: String) {
        guard let feature = panel.feature else { return }
        let inserted: String
        let original: String
        if feature.replacesSource {
            guard let source = aiSource else { panel.set(phase: .failed(.emptySource)); return }
            if source.isSelection {
                input.replaceSelection(with: result)
            } else if !input.replaceTextBeforeCursor(source.text, with: result) {
                panel.set(phase: .failed(.textChanged))
                return
            }
            inserted = result
            original = source.text
        } else {
            inserted = input.insertAIText(result)
            original = ""
        }
        lastAIApplication = (inserted, original)
        feedback.swipeCommit()
        view.isAIVisible = false
        input.refresh()
    }

    func aiPanelDidTapLetters(_ panel: AIPanelView) {
        ai.cancel()
        view.suggestionBar.aiButton.isBusy = false
        view.isAIVisible = false
        input.refresh()
    }

    func aiPanelDidTapUndo(_ panel: AIPanelView) {
        guard let last = lastAIApplication, input.replaceTextBeforeCursor(last.inserted, with: last.original) else {
            panel.canUndo = false
            return
        }
        lastAIApplication = nil
        panel.canUndo = false
        feedback.deleteTap()
        view.isAIVisible = false
        input.refresh()
    }

    func aiPanelDidTapSettings(_ panel: AIPanelView) { onOpenSettings?() }
}
