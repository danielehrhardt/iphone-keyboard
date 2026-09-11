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
    var needsGlobeKey = false { didSet { if needsGlobeKey != oldValue { refreshLayoutOptions() } } }
    var isPhoneIdiom = true

    private(set) var currentLayer: KeyboardLayer = .letters
    private var layoutOptions = LayoutOptions()
    private var lastGridSize: CGSize = .zero
    private var lastGridLayer: KeyboardLayer?
    private var lastOptions: LayoutOptions?
    private var lastMetrics: KeyboardGeometry.Metrics?
    private var screenSize: CGSize = .zero
    private var traits: UITraitCollection

    init(settings: KeyboardSettings, proxy: TextProxy, engine: KeyboardEngine?, traits: UITraitCollection) {
        self.settings = settings
        self.traits = traits
        feedback = Feedback(settings: settings)
        let theme = KeyboardTheme.current(traits: traits, settings: settings)
        view = KeyboardView(theme: theme, feedback: feedback)
        input = InputController(engine: engine, settings: settings, proxy: proxy)
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
        view.onLayout = { [weak self] in self?.rebuildGridIfNeeded() }
    }

    // MARK: Environment

    var engine: KeyboardEngine? {
        get { input.engine }
        set { input.engine = newValue; input.refresh() }
    }

    /// Picks up personal-dictionary changes made by the other process (app ↔ extension).
    func willAppear() {
        input.engine?.user.reloadIfChanged()
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
        layoutOptions = LayoutOptions(needsGlobeKey: needsGlobeKey, showsEmojiKey: true,
                                      isEmailOrURL: input.traits.isEmailOrURL, showsCommaKey: settings.commaKey)
        view.setNeedsLayout()
    }

    private func rebuildGridIfNeeded() {
        let size = view.grid.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        if screenSize == .zero { screenSize = view.window?.windowScene?.screen.bounds.size ?? CGSize(width: size.width, height: size.width * 2) }
        let metrics = KeyboardMetrics.layoutMetrics(for: traits, screenSize: screenSize)
        if size != lastGridSize || lastGridLayer != currentLayer || lastOptions != layoutOptions || lastMetrics != metrics {
            lastGridSize = size; lastGridLayer = currentLayer; lastOptions = layoutOptions; lastMetrics = metrics
            let layout = GermanLayouts.layout(for: currentLayer, options: layoutOptions)
            view.grid.configure(layout: layout, metrics: metrics)
            input.keyMap = view.grid.keyMap
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
        view.suggestionBar.set(state.suggestions)
    }

    func inputControllerRequestsGlobe(_ c: InputController) { onGlobe?() }
    func inputControllerRequestsEmoji(_ c: InputController) { view.isEmojiVisible = true }
    func inputControllerRequestsDismiss(_ c: InputController) { onDismiss?() }
}

// MARK: - KeyGridDelegate

extension KeyboardCoordinator: KeyGridDelegate {
    var swipeTypingEnabled: Bool { settings.swipeTyping && input.traits.allowsSwipe && input.engine != nil }
    var keyPreviewEnabled: Bool { settings.keyPreview && isPhoneIdiom }
    var swipeTrailEnabled: Bool { settings.swipeTrail }
    var longPressNumbersEnabled: Bool { settings.longPressNumbers }

    func keyGrid(_ grid: KeyGridView, didTap key: Key) { input.handle(key: key) }
    func keyGrid(_ grid: KeyGridView, didInsertAlternate text: String, for key: Key) { input.insertAlternate(text, for: key) }
    func keyGrid(_ grid: KeyGridView, didSwipe path: [CGPoint], keyMap: KeyMap) {
        let fallback = path.last.flatMap { grid.geometry?.keyFrame(at: $0)?.key }
        input.handleSwipe(path: path, keyMap: keyMap, fallbackKey: fallback)
    }
    /// Keys without alternates (space, return …) have no long-press action; the touch stays pending
    /// and commits as a normal tap on release.
    func keyGrid(_ grid: KeyGridView, didLongPress key: Key) {}
    func keyGrid(_ grid: KeyGridView, globeTouchEvent event: UIEvent?) { onGlobeEvent?(grid, event) }
    func keyGridBackspaceRepeat(_ grid: KeyGridView, wordwise: Bool) { input.backspaceRepeat(wordwise: wordwise) }
    func keyGrid(_ grid: KeyGridView, moveCursorBy offset: Int) { input.moveCursor(by: offset) }
    func keyGridDidDoubleTapShift(_ grid: KeyGridView) { input.lockShift() }
    func keyGrid(_ grid: KeyGridView, didShiftSlideTo key: Key) { input.shiftSlide(to: key) }
}

// MARK: - EmojiPanelDelegate

extension KeyboardCoordinator: EmojiPanelDelegate {
    func emojiPanel(_ panel: EmojiPanelView, didPick emoji: String) {
        input.proxy.insert(emoji)
        feedback.keyTap()
        input.textDidChangeExternally()
    }

    func emojiPanelDidTapBackspace(_ panel: EmojiPanelView) {
        input.proxy.deleteBackward()
        feedback.deleteTap()
        input.textDidChangeExternally()
    }

    func emojiPanelDidTapLetters(_ panel: EmojiPanelView) {
        view.isEmojiVisible = false
        input.refresh()
    }
}
