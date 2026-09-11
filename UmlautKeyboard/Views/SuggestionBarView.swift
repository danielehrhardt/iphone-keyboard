import UIKit

struct Suggestion: Equatable {
    enum Kind: Equatable { case primary, alternate, literal, prediction }
    let text: String
    let kind: Kind
    var display: String { kind == .literal ? "„\(text)“" : text }
}

/// Three suggestion cells with hairline dividers, the primary one in the middle and bold.
final class SuggestionBarView: UIView {
    var onSelect: ((Suggestion) -> Void)?
    private var buttons: [UIButton] = []
    private var dividers: [UIView] = []
    private(set) var suggestions: [Suggestion] = []
    private var theme: KeyboardTheme

    init(theme: KeyboardTheme) {
        self.theme = theme
        super.init(frame: .zero)
        for i in 0..<3 {
            let b = UIButton(type: .custom)
            b.tag = i
            b.titleLabel?.lineBreakMode = .byTruncatingTail
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.7
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            b.addTarget(self, action: #selector(highlight(_:)), for: [.touchDown, .touchDragEnter])
            b.addTarget(self, action: #selector(unhighlight(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
            b.layer.cornerRadius = 6
            b.layer.cornerCurve = .continuous
            addSubview(b)
            buttons.append(b)
        }
        for _ in 0..<2 {
            let d = UIView()
            addSubview(d)
            dividers.append(d)
        }
        apply(theme: theme)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        dividers.forEach { $0.backgroundColor = theme.suggestionDivider }
        render()
    }

    func set(_ new: [Suggestion]) {
        guard new != suggestions else { return }
        suggestions = new
        render()
    }

    private func render() {
        for (i, b) in buttons.enumerated() {
            let s = suggestions.indices.contains(i) ? suggestions[i] : nil
            let weight: UIFont.Weight = s?.kind == .primary ? .semibold : .regular
            let size: CGFloat = traitCollection.userInterfaceIdiom == .pad ? 19 : 17
            b.setTitle(s?.display, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: size, weight: weight)
            b.setTitleColor(theme.suggestionText, for: .normal)
            b.isHidden = s == nil
            b.accessibilityLabel = s.map { "Vorschlag \($0.text)" }
        }
        let visible = suggestions.count
        dividers[0].isHidden = visible < 2
        dividers[1].isHidden = visible < 3
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width / 3
        let inset: CGFloat = 4
        for (i, b) in buttons.enumerated() {
            b.frame = CGRect(x: CGFloat(i) * w + inset, y: 4, width: w - inset * 2, height: bounds.height - 8)
        }
        for (i, d) in dividers.enumerated() {
            d.frame = CGRect(x: w * CGFloat(i + 1) - 0.5, y: bounds.height * 0.25, width: 1, height: bounds.height * 0.5)
        }
    }

    @objc private func tapped(_ sender: UIButton) {
        guard suggestions.indices.contains(sender.tag) else { return }
        onSelect?(suggestions[sender.tag])
    }

    @objc private func highlight(_ sender: UIButton) { sender.backgroundColor = theme.suggestionHighlight }
    @objc private func unhighlight(_ sender: UIButton) { sender.backgroundColor = .clear }
}
