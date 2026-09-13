import UIKit

/// Thin abstraction over `UITextDocumentProxy` so the input logic can be exercised without UIKit.
protocol TextProxy: AnyObject {
    var textBefore: String { get }
    var textAfter: String { get }
    func insert(_ text: String)
    func deleteBackward()
    func moveCursor(by offset: Int)
    /// The selected text, if the host exposes it (the AI panel works on a selection first).
    var selectedText: String? { get }
}

extension TextProxy {
    var selectedText: String? { nil }
}

extension UITextDocumentProxy {
    var textBefore: String { documentContextBeforeInput ?? "" }
    var textAfter: String { documentContextAfterInput ?? "" }
}

final class DocumentProxyAdapter: TextProxy {
    private let proxy: () -> UITextDocumentProxy
    init(proxy: @escaping () -> UITextDocumentProxy) { self.proxy = proxy }
    var textBefore: String { proxy().textBefore }
    var textAfter: String { proxy().textAfter }
    func insert(_ text: String) { proxy().insertText(text) }
    func deleteBackward() { proxy().deleteBackward() }
    func moveCursor(by offset: Int) { proxy().adjustTextPosition(byCharacterOffset: offset) }
    var selectedText: String? {
        guard let s = proxy().selectedText, !s.isEmpty else { return nil }
        return s
    }
}

/// Field traits that change keyboard behaviour.
struct FieldTraits: Equatable {
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .default
    var autocapitalization: UITextAutocapitalizationType = .sentences
    var autocorrectionDisabled = false
    var isSecure = false

    init() {}

    init(proxy: UITextDocumentProxy) {
        keyboardType = proxy.keyboardType ?? .default
        returnKeyType = proxy.returnKeyType ?? .default
        autocapitalization = proxy.autocapitalizationType ?? .sentences
        autocorrectionDisabled = proxy.autocorrectionType == .no
        isSecure = proxy.isSecureTextEntry ?? false
    }

    var isEmailOrURL: Bool {
        keyboardType == .emailAddress || keyboardType == .URL
    }

    var isNumeric: Bool {
        switch keyboardType {
        case .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad, .namePhonePad: return keyboardType != .namePhonePad
        default: return false
        }
    }

    /// Passwords, addresses and numbers: no learning, no guessing.
    var isSensitive: Bool { isSecure || isEmailOrURL || isNumeric }
    /// Glide typing works wherever words are typed.
    var allowsSwipe: Bool { !isSensitive }
    /// Suggestion strip (predictions/completions) and learning of typed words.
    var allowsSuggestions: Bool { !isSensitive && keyboardType != .asciiCapable }
    /// Silent replacement of typed words – off when the field asked for no autocorrection.
    var allowsAutocorrect: Bool { allowsSuggestions && !autocorrectionDisabled }

    var returnLabel: String? {
        switch returnKeyType {
        case .go: return "Los"
        case .google, .search, .yahoo: return "Suchen"
        case .send: return "Senden"
        case .next: return "Weiter"
        case .done: return "Fertig"
        case .join: return "Verbinden"
        case .continue: return "Weiter"
        case .route: return "Route"
        case .emergencyCall: return "Notruf"
        default: return nil
        }
    }

    var returnIsAccented: Bool {
        switch returnKeyType {
        case .go, .google, .search, .yahoo, .send, .done, .join, .route: return true
        default: return false
        }
    }
}
