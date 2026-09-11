import UIKit
import KeyboardCore

/// Glues `KeyboardView`, `InputController` and the engine together. Used by the extension's
/// `KeyboardViewController` and by the host app's in-app demo keyboard, so both behave identically.
final class KeyboardCoordinator: NSObject {

    let settings: KeyboardSettings
    let feedback: Feedback
    let view: KeyboardView
    let input: InputController

    /// Hooks the owner provides (extension: system APIs; in-app demo: no-ops).
    var onGlobe: (() -> Void)?
    /// Raw touch events from the globe key (extension wires this to `handleInputModeList`).
    var onGlobeEvent: ((UIView, UIEvent?) -> Void)?
    var onDismiss: (() -> Void)?
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

    init(settings: KeyboardSettings, proxy: TextProxy, engine: KeyboardEngine?, traits: UITraitCollection, tapMap: TapMap? = .standard) {
        self.settings = settings
        self.traits = traits
        language = settings.currentLanguage
        feedback = Feedback(settings: settings)
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
        // The app may have switched the current language off meanwhile.
        select(language: settings.currentLanguage)
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
                                    language: language, showsLanguageName: settings.hasMultipleLanguages)
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
    }

    func inputControllerRequestsGlobe(_ c: InputController) { onGlobe?() }
    func inputControllerRequestsEmoji(_ c: InputController) {
        // Reached from a hold on the comma key with the finger still down: the grid is about to be
        // hidden, so end its touches here rather than waiting for a lift it may never see.
        view.grid.cancelAllTouches()
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
