import SwiftUI
import UIKit
import KeyboardCore

/// Loads the shared engine once for the in-app demo keyboard.
@MainActor
final class DemoEngineLoader: ObservableObject {
    static let shared = DemoEngineLoader()
    @Published private(set) var engine: KeyboardEngine?

    init() {
        Task.detached(priority: .userInitiated) {
            let engine = try? KeyboardEngine()
            await MainActor.run { self.engine = engine }
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

        func attach(_ tv: UITextView, useUmlaut: Bool, engine: KeyboardEngine?) {
            usingUmlaut = useUmlaut
            if useUmlaut {
                let d = DemoKeyboardView(textView: tv, engine: engine)
                demo = d
                tv.inputView = d
            }
        }

        func update(_ tv: UITextView, useUmlaut: Bool, engine: KeyboardEngine?, settingsVersion: Int) {
            if useUmlaut != usingUmlaut {
                usingUmlaut = useUmlaut
                if useUmlaut {
                    let d = DemoKeyboardView(textView: tv, engine: engine)
                    demo = d
                    tv.inputView = d
                } else {
                    demo = nil
                    tv.inputView = nil
                }
                tv.reloadInputViews()
            }
            if let demo, demo.engine == nil, let engine { demo.engine = engine }
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
