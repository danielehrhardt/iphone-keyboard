import UIKit

/// `TextProxy` backed by a `UITextView` inside the host app, so the exact keyboard UI can be
/// tried in-app before the extension is enabled.
final class TextViewProxy: TextProxy {
    private weak var textView: UITextView?

    init(textView: UITextView) { self.textView = textView }

    var textBefore: String {
        guard let tv = textView, let range = tv.selectedTextRange else { return "" }
        return tv.text(in: tv.textRange(from: tv.beginningOfDocument, to: range.start)!) ?? ""
    }

    var textAfter: String {
        guard let tv = textView, let range = tv.selectedTextRange else { return "" }
        return tv.text(in: tv.textRange(from: range.end, to: tv.endOfDocument)!) ?? ""
    }

    func insert(_ text: String) { textView?.insertText(text) }

    var selectedText: String? {
        guard let tv = textView, let range = tv.selectedTextRange, !range.isEmpty else { return nil }
        return tv.text(in: range)
    }

    func deleteBackward() { textView?.deleteBackward() }

    func moveCursor(by offset: Int) {
        guard let tv = textView, let range = tv.selectedTextRange,
              let pos = tv.position(from: range.start, offset: offset) else { return }
        tv.selectedTextRange = tv.textRange(from: pos, to: pos)
    }
}
