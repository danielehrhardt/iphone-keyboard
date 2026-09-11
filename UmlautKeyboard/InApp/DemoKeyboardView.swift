import UIKit
import KeyboardCore

/// The real keyboard, hosted inside the app as a text view's `inputView`, so people can try
/// swipe typing before enabling the extension. Compiled into the app target only.
///
/// A `UIInputView` in keyboard style, so the system paints the same translucent material
/// behind it that the extension gets for free.
final class DemoKeyboardView: UIInputView {
    private let coordinator: KeyboardCoordinator
    private let settings: KeyboardSettings
    private weak var textView: UITextView?
    private var observers: [NSObjectProtocol] = []
    /// Keys + suggestion bar; the bottom safe area is added on top once known.
    private var contentHeight: CGFloat

    init(textView: UITextView, engine: KeyboardEngine?, settings: KeyboardSettings = .shared) {
        self.textView = textView
        self.settings = settings
        coordinator = KeyboardCoordinator(settings: settings, proxy: TextViewProxy(textView: textView), engine: engine, traits: textView.traitCollection)
        let screen = textView.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        contentHeight = coordinator.updateEnvironment(traits: textView.traitCollection, screenSize: screen)
        super.init(frame: CGRect(x: 0, y: 0, width: screen.width, height: contentHeight), inputViewStyle: .keyboard)
        autoresizingMask = [.flexibleWidth]
        backgroundColor = .clear
        overrideUserInterfaceStyle = KeyboardTheme.interfaceStyle(for: settings)
        coordinator.needsGlobeKey = false
        coordinator.onDismiss = { [weak textView] in textView?.resignFirstResponder() }
        var traits = FieldTraits()
        traits.returnKeyType = textView.returnKeyType
        traits.autocapitalization = textView.autocapitalizationType
        coordinator.setFieldTraits(traits)
        coordinator.view.frame = bounds
        coordinator.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(coordinator.view)

        observers.append(NotificationCenter.default.addObserver(forName: UITextView.textDidChangeNotification, object: textView, queue: .main) { [weak self] _ in
            self?.coordinator.input.textDidChangeExternally()
        })
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    var engine: KeyboardEngine? {
        get { coordinator.engine }
        set { coordinator.engine = newValue }
    }

    /// Call when the text view's selection changed (e.g. from `textViewDidChangeSelection`).
    func selectionChanged() { coordinator.input.textDidChangeExternally() }

    /// Re-reads theme/accent/key size from settings.
    func settingsChanged() {
        overrideUserInterfaceStyle = KeyboardTheme.interfaceStyle(for: settings)
        let screen = window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        contentHeight = coordinator.updateEnvironment(traits: traitCollection, screenSize: screen)
        applyHeight()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        applyHeight()
    }

    /// Grows the input view by the home-indicator inset when the system lets it reach the screen edge.
    private func applyHeight() {
        let h = contentHeight + safeAreaInsets.bottom
        if abs(h - bounds.height) > 0.5 {
            frame.size.height = h
            invalidateIntrinsicContentSize()
            textView?.reloadInputViews()
        }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: bounds.height) }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { settingsChanged() }
    }
}
