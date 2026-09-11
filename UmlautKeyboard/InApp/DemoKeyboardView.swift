import UIKit
import KeyboardCore

/// The real keyboard, hosted inside the app as a text view's `inputView`, so people can try
/// swipe typing before enabling the extension. Compiled into the app target only.
final class DemoKeyboardView: UIView {
    private let coordinator: KeyboardCoordinator
    private weak var textView: UITextView?
    private var observers: [NSObjectProtocol] = []

    init(textView: UITextView, engine: KeyboardEngine?, settings: KeyboardSettings = .shared) {
        self.textView = textView
        coordinator = KeyboardCoordinator(settings: settings, proxy: TextViewProxy(textView: textView), engine: engine, traits: textView.traitCollection)
        let screen = textView.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        let height = coordinator.updateEnvironment(traits: textView.traitCollection, screenSize: screen)
        super.init(frame: CGRect(x: 0, y: 0, width: screen.width, height: height))
        autoresizingMask = [.flexibleWidth]
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
        let screen = window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        let h = coordinator.updateEnvironment(traits: traitCollection, screenSize: screen)
        if abs(h - bounds.height) > 0.5 {
            frame.size.height = h
            textView?.reloadInputViews()
        }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: bounds.height) }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { settingsChanged() }
    }
}
