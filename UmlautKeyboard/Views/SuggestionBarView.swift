import UIKit

struct Suggestion: Equatable {
    enum Kind: Equatable { case primary, alternate, literal, prediction }
    let text: String
    let kind: Kind
    var display: String { kind == .literal ? "„\(text)“" : text }
}

/// Three suggestion cells with hairline dividers, the primary one in the middle and bold.
/// Cells highlight as soft pills and new suggestions fade in instead of snapping. A small
/// "hide keyboard" button sits at the trailing edge (iPhone has no system dismiss key).
final class SuggestionBarView: UIView {
    var onSelect: ((Suggestion) -> Void)?
    var onDismiss: (() -> Void)?
    private var buttons: [UIButton] = []
    /// Visual pill per cell. The button itself spans the whole cell so the tap target is large;
    /// only this inset view shows the highlight.
    private var pills: [UIView] = []
    private var dividers: [UIView] = []
    private let dismissButton = UIButton(type: .system)
    private static let dismissWidth: CGFloat = 46
    private static let dismissInset: CGFloat = 6
    private(set) var suggestions: [Suggestion] = []
    private var theme: KeyboardTheme

    init(theme: KeyboardTheme) {
        self.theme = theme
        super.init(frame: .zero)
        backgroundColor = .clear
        for i in 0..<3 {
            let b = UIButton(type: .custom)
            b.tag = i
            b.titleLabel?.lineBreakMode = .byTruncatingTail
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.7
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            b.addTarget(self, action: #selector(highlight(_:)), for: [.touchDown, .touchDragEnter])
            b.addTarget(self, action: #selector(unhighlight(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
            b.accessibilityIdentifier = "suggestion-\(i)"
            let pill = UIView()
            pill.isUserInteractionEnabled = false
            pill.layer.cornerCurve = .continuous
            b.insertSubview(pill, at: 0)
            pills.append(pill)
            addSubview(b)
            buttons.append(b)
        }
        for _ in 0..<2 {
            let d = UIView()
            addSubview(d)
            dividers.append(d)
        }
        dismissButton.accessibilityLabel = "Tastatur ausblenden"
        dismissButton.accessibilityIdentifier = "dismiss-keyboard"
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        addSubview(dismissButton)
        apply(theme: theme)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        dividers.forEach { $0.backgroundColor = theme.suggestionDivider }
        configureDismissButton()
        render()
    }

    /// Liquid-glass capsule on iOS 26, a flat translucent capsule before that.
    private func configureDismissButton() {
        let image = UIImage(systemName: "keyboard.chevron.compact.down",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) {
            config = .glass()
        } else {
            config = .plain()
            config.background.backgroundColor = theme.suggestionHighlight
        }
        config.cornerStyle = .capsule
        config.image = image
        config.baseForegroundColor = theme.suggestionText
        config.contentInsets = .zero
        dismissButton.configuration = config
        dismissButton.tintColor = theme.suggestionText
    }

    func set(_ new: [Suggestion]) {
        guard new != suggestions else { return }
        let hadContent = !suggestions.isEmpty
        suggestions = new
        render()
        // A soft fade when the strip fills after being empty (e.g. first letter of a word).
        if !hadContent, !new.isEmpty {
            buttons.forEach { $0.titleLabel?.alpha = 0 }
            UIView.animate(withDuration: 0.16, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
                self.buttons.forEach { $0.titleLabel?.alpha = 1 }
            }
        }
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
        let reserved = Self.dismissWidth + Self.dismissInset * 2
        let w = max(bounds.width - reserved, 0) / 3
        let inset: CGFloat = 6
        let h = bounds.height - 12
        dismissButton.frame = CGRect(x: bounds.width - Self.dismissInset - Self.dismissWidth,
                                     y: (bounds.height - min(h, 32)) / 2,
                                     width: Self.dismissWidth, height: min(h, 32))
        // The button covers its whole third of the strip (full height, no gaps) so a tap anywhere
        // near the word registers; the pill inside carries the inset look.
        for (i, b) in buttons.enumerated() {
            b.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: bounds.height)
            let pill = pills[i]
            pill.frame = CGRect(x: inset, y: 6, width: max(w - inset * 2, 0), height: max(h, 0))
            pill.layer.cornerRadius = min(max(h, 0) / 2, 12)
        }
        for (i, d) in dividers.enumerated() {
            d.frame = CGRect(x: w * CGFloat(i + 1) - 0.5, y: bounds.height * 0.3, width: 1, height: bounds.height * 0.4)
        }
    }

    @objc private func tapped(_ sender: UIButton) {
        guard suggestions.indices.contains(sender.tag) else { return }
        onSelect?(suggestions[sender.tag])
    }

    @objc private func dismissTapped() { onDismiss?() }

    @objc private func highlight(_ sender: UIButton) {
        pills[safe: sender.tag]?.backgroundColor = theme.suggestionHighlight
    }

    @objc private func unhighlight(_ sender: UIButton) {
        guard let pill = pills[safe: sender.tag] else { return }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            pill.backgroundColor = .clear
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
