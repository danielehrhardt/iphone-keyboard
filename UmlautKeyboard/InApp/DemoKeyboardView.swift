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
    private var heightConstraint: NSLayoutConstraint!

    init(textView: UITextView, engine: KeyboardEngine?, settings: KeyboardSettings = .shared,
         engineProvider: ((KeyboardLanguage, @escaping (KeyboardEngine?) -> Void) -> Void)? = nil) {
        self.textView = textView
        self.settings = settings
        coordinator = KeyboardCoordinator(settings: settings, proxy: TextViewProxy(textView: textView), engine: engine, traits: textView.traitCollection)
        coordinator.engineProvider = engineProvider
        let screen = textView.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        contentHeight = coordinator.updateEnvironment(traits: textView.traitCollection, screenSize: screen)
        super.init(frame: CGRect(x: 0, y: 0, width: screen.width, height: contentHeight), inputViewStyle: .keyboard)
        // Self-sizing through a height constraint is the only way UIKit honours later height
        // changes of a custom input view (the safe-area strip is added once the view is on screen).
        allowsSelfSizing = true
        translatesAutoresizingMaskIntoConstraints = false
        heightConstraint = heightAnchor.constraint(equalToConstant: contentHeight)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true
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

    /// The language the demo keyboard is typing in.
    var language: KeyboardLanguage { coordinator.language }

    /// Call when the text view's selection changed (e.g. from `textViewDidChangeSelection`).
    func selectionChanged() { coordinator.input.textDidChangeExternally() }

    /// Re-reads theme/accent/key size and the language settings.
    func settingsChanged() {
        overrideUserInterfaceStyle = KeyboardTheme.interfaceStyle(for: settings)
        let screen = window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        contentHeight = coordinator.updateEnvironment(traits: traitCollection, screenSize: screen)
        coordinator.willAppear()
        applyHeight()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        applyHeight()
    }

    /// Grows the input view by the home-indicator inset when the system lets it reach the screen edge.
    private func applyHeight() {
        let h = contentHeight + safeAreaInsets.bottom
        guard abs(h - heightConstraint.constant) > 0.5 else { return }
        heightConstraint.constant = h
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: heightConstraint.constant) }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { settingsChanged() }
    }
}
