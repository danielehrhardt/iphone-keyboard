import SwiftUI
import UIKit
import KeyboardCore

/// Loads the engines for the in-app demo keyboard, one per language, each once. The app has no
/// extension memory budget, so engines of every language the user tried stay cached.
@MainActor
final class DemoEngineLoader: ObservableObject {
    static let shared = DemoEngineLoader()
    /// The engine of the current typing language, once loaded.
    @Published private(set) var engine: KeyboardEngine?

    private var engines: [KeyboardLanguage: KeyboardEngine] = [:]
    private var waiters: [KeyboardLanguage: [(KeyboardEngine?) -> Void]] = [:]

    init() {
        load(KeyboardSettings.shared.currentLanguage) { [weak self] in self?.engine = $0 }
    }

    /// Hands out the engine for `language`, loading it in the background on first use.
    func load(_ language: KeyboardLanguage, completion: @escaping (KeyboardEngine?) -> Void) {
        if let engine = engines[language] { completion(engine); return }
        let isLoading = waiters[language] != nil
        waiters[language, default: []].append(completion)
        guard !isLoading else { return }
        Task.detached(priority: .userInitiated) {
            let engine = try? KeyboardEngine(language: language)
            await MainActor.run {
                if let engine { self.engines[language] = engine }
                let pending = self.waiters.removeValue(forKey: language) ?? []
                pending.forEach { $0(engine) }
            }
        }
    }
}

/// A `UITextView` whose input view is the real Umlaut keyboard, so swipe typing can be tried
/// before the extension is enabled in Settings.
struct DemoTextView: UIViewRepresentable {
    @Binding var text: String
    var useUmlautKeyboard: Bool
    var engine: KeyboardEngine?
    var settingsVersion: Int
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        tv.delegate = context.coordinator
        tv.autocorrectionType = .default   // Umlaut honours fields that turn autocorrection off
        tv.spellCheckingType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.autocapitalizationType = .sentences
        tv.returnKeyType = .default
        tv.keyboardType = .default
        tv.text = text
        context.coordinator.attach(tv, useUmlaut: useUmlautKeyboard, engine: engine)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text { tv.text = text }
        context.coordinator.update(tv, useUmlaut: useUmlautKeyboard, engine: engine, settingsVersion: settingsVersion)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: DemoTextView
        private var demo: DemoKeyboardView?
        private var usingUmlaut = false
        private var lastSettingsVersion = -1

        init(_ parent: DemoTextView) { self.parent = parent }

        private func makeDemo(_ tv: UITextView, engine: KeyboardEngine?) -> DemoKeyboardView {
            DemoKeyboardView(textView: tv, engine: engine) { language, completion in
                DemoEngineLoader.shared.load(language, completion: completion)
            }
        }

        func attach(_ tv: UITextView, useUmlaut: Bool, engine: KeyboardEngine?) {
            usingUmlaut = useUmlaut
            if useUmlaut {
                let d = makeDemo(tv, engine: engine)
                demo = d
                tv.inputView = d
            }
        }

        func update(_ tv: UITextView, useUmlaut: Bool, engine: KeyboardEngine?, settingsVersion: Int) {
            if useUmlaut != usingUmlaut {
                usingUmlaut = useUmlaut
                if useUmlaut {
                    let d = makeDemo(tv, engine: engine)
                    demo = d
                    tv.inputView = d
                } else {
                    demo = nil
                    tv.inputView = nil
                }
                tv.reloadInputViews()
            }
            if let demo, demo.engine == nil, let engine, engine.language == demo.language { demo.engine = engine }
            if settingsVersion != lastSettingsVersion {
                lastSettingsVersion = settingsVersion
                demo?.settingsChanged()
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            demo?.selectionChanged()
        }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocusChange(true) }
        func textViewDidEndEditing(_ textView: UITextView) { parent.onFocusChange(false) }
    }
}
