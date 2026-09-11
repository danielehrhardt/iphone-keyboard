import UIKit
import os.log
import KeyboardCore

private let log = Logger(subsystem: "de.codext.umlaut.keyboard", category: "engine")

/// Entry point of the extension: hosts a `KeyboardCoordinator` bound to the document proxy and
/// keeps the keyboard height right for the current device and orientation.
final class KeyboardViewController: UIInputViewController {

    /// The engine survives across text fields while the extension process is alive. Only the
    /// active language's engine is kept: a second lexicon would cost another ~14 MB of the
    /// extension's tight memory budget, and reloading one takes well under a second.
    private static var sharedEngine: KeyboardEngine?
    private static var loadingLanguage: KeyboardLanguage?
    private static var engineWaiters: [(language: KeyboardLanguage, completion: (KeyboardEngine?) -> Void)] = []

    private let settings = KeyboardSettings.shared
    private var coordinator: KeyboardCoordinator!
    private var heightConstraint: NSLayoutConstraint?

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        log.notice("keyboard view loading, footprint \(Self.footprintMB, format: .fixed(precision: 1)) MB")
        let proxy = DocumentProxyAdapter(proxy: { [unowned self] in self.textDocumentProxy })
        coordinator = KeyboardCoordinator(settings: settings, proxy: proxy, engine: Self.sharedEngine, traits: traitCollection)
        coordinator.onGlobe = { [weak self] in self?.advanceToNextInputMode() }
        coordinator.onGlobeEvent = { [weak self] from, event in
            guard let self else { return }
            if let event { self.handleInputModeList(from: from, with: event) }
        }
        coordinator.onDismiss = { [weak self] in self?.dismissKeyboard() }
        coordinator.engineProvider = { language, completion in Self.loadEngine(language: language, completion) }

        // Transparent: the system draws its keyboard material (Liquid Glass on iOS 26) behind us,
        // and follows the forced light/dark theme via the interface-style override.
        view.backgroundColor = .clear
        view.overrideUserInterfaceStyle = KeyboardTheme.interfaceStyle(for: settings)
        let kv = coordinator.view
        kv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(kv)
        NSLayoutConstraint.activate([
            kv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            kv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            kv.topAnchor.constraint(equalTo: view.topAnchor),
            kv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        (inputView as? UIInputView)?.allowsSelfSizing = true

        Self.loadEngine(language: coordinator.language) { [weak self] engine in
            guard let engine else { return }
            self?.coordinator.engine = engine
            for delay in [3.0, 8.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    log.notice("footprint \(Int(delay))s after engine load \(Self.footprintMB, format: .fixed(precision: 1)) MB")
                }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.overrideUserInterfaceStyle = KeyboardTheme.interfaceStyle(for: settings)
        coordinator.willAppear()
        coordinator.needsGlobeKey = needsInputModeSwitchKey
        coordinator.setFieldTraits(FieldTraits(proxy: textDocumentProxy))
        updateHeight()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Only reliable once the view is in the hierarchy.
        coordinator.needsGlobeKey = needsInputModeSwitchKey
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        self.coordinator.cancelTouches()
        coordinator.animate(alongsideTransition: { _ in
            self.updateHeight(for: size)
        })
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updateHeight()
        }
    }

    /// The home indicator strip (and the notch in landscape) only become known once the view is
    /// in the keyboard window; grow the keyboard so the keys sit above it like the system keyboard.
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateHeight()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        coordinator.needsGlobeKey = needsInputModeSwitchKey
        coordinator.setFieldTraits(FieldTraits(proxy: textDocumentProxy))
        coordinator.input.textDidChangeExternally()
    }

    // MARK: Engine

    /// Hands out the engine for `language`, loading it in the background if it isn't the one
    /// kept in memory. Loads run one at a time so two lexicons never sit in memory together;
    /// a request for another language queues up behind the running load.
    private static func loadEngine(language: KeyboardLanguage, _ completion: @escaping (KeyboardEngine?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))     // the statics above are main-thread state
        if let e = sharedEngine, e.language == language { completion(e); return }
        engineWaiters.append((language, completion))
        guard loadingLanguage == nil else { return }
        loadingLanguage = language
        // The previous language's lexicon goes before the new one is built, so two never coexist
        // (the coordinator has already dropped its reference in `select(language:)`).
        sharedEngine = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let start = CFAbsoluteTimeGetCurrent()
            let engine: KeyboardEngine?
            do {
                engine = try KeyboardEngine(language: language)
                log.notice("\(language.rawValue) engine loaded in \(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 3))s, \(engine?.lexicon.count ?? 0) words, footprint \(Self.footprintMB, format: .fixed(precision: 1)) MB")
            } catch {
                engine = nil
                log.error("\(language.rawValue) engine failed to load: \(String(describing: error))")
            }
            DispatchQueue.main.async {
                loadingLanguage = nil
                // Kept only while it is still the language being typed: a switch back during the
                // load makes this engine stale, and the queued request below loads the right one.
                if let engine, engine.language == KeyboardSettings.shared.currentLanguage { sharedEngine = engine }
                let served = engineWaiters.filter { $0.language == language }
                engineWaiters.removeAll { $0.language == language }
                served.forEach { $0.completion(engine) }
                // Requests for another language that queued up behind this load.
                let pending = engineWaiters
                engineWaiters.removeAll()
                pending.forEach { loadEngine(language: $0.language, $0.completion) }
            }
        }
    }

    /// Physical memory footprint of this process in MB (keyboard extensions are killed around 60–70 MB).
    private static var footprintMB: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    // MARK: Height

    private var screenSize: CGSize {
        view.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
    }

    private func updateHeight(for size: CGSize? = nil) {
        // During rotation `size` is the new keyboard width; derive the matching screen orientation.
        let current = screenSize
        let longSide = max(current.width, current.height), shortSide = min(current.width, current.height)
        let screen: CGSize
        if let size {
            screen = size.width > shortSide ? CGSize(width: longSide, height: shortSide) : CGSize(width: shortSide, height: longSide)
        } else {
            screen = current
        }
        let total = coordinator.updateEnvironment(traits: traitCollection, screenSize: screen) + view.safeAreaInsets.bottom
        if let c = heightConstraint {
            c.constant = total
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: total)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
    }
}
