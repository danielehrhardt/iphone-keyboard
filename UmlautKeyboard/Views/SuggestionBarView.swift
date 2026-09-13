import UIKit
import KeyboardCore

struct Suggestion: Equatable {
    /// `.ai` is a result of the assistant (a corrected sentence, a continuation), marked with ✦.
    enum Kind: Equatable { case primary, alternate, literal, prediction, ai }
    let text: String
    let kind: Kind
    var display: String {
        switch kind {
        case .literal: return "„\(text)“"
        case .ai: return "✦ \(text)"
        default: return text
        }
    }
}

/// Three suggestion cells with hairline dividers, the primary one in the middle and bold.
/// Cells highlight as soft pills and new suggestions fade in instead of snapping. A "⋯" button
/// at the leading edge opens the action menu (clipboard history, emoji …). A small "hide
/// keyboard" button sits at the trailing edge (iPhone has no system dismiss key), and while
/// several typing languages are enabled a language badge ("DE", "EN") sits next to it: tapping
/// it switches to the next language.
final class SuggestionBarView: UIView {
    var onSelect: ((Suggestion) -> Void)?
    var onDismiss: (() -> Void)?
    var onLanguage: (() -> Void)?
    var onActions: (() -> Void)?
    var onAI: (() -> Void)?
    private var buttons: [UIButton] = []
    /// Visual pill per cell. The button itself spans the whole cell so the tap target is large;
    /// only this inset view shows the highlight.
    private var pills: [UIView] = []
    private var dividers: [UIView] = []
    private let dismissButton = UIButton(type: .system)
    private let languageButton = UIButton(type: .system)
    let actionsButton = UIButton(type: .system)
    /// The sparkles capsule that opens the AI panel; hidden while the assistant is off.
    let aiButton = AIStripButton()
    static let aiWidth: CGFloat = 44
    static let dismissWidth: CGFloat = 46
    static let languageWidth: CGFloat = 44
    static let actionsWidth: CGFloat = 46
    static let dismissInset: CGFloat = 6
    /// Width taken by the "⋯" button and its inset at the leading edge.
    static var leadingReserved: CGFloat { actionsWidth + dismissInset }
    /// Width taken by the dismiss button (and the language badge, when shown) at the trailing edge.
    static func trailingReserved(hasLanguage: Bool, hasAI: Bool = false) -> CGFloat {
        dismissWidth + dismissInset * 2 + (hasLanguage ? languageWidth + dismissInset : 0) + (hasAI ? aiWidth + dismissInset : 0)
    }

    /// Whether the AI button is shown (the assistant is switched on in the app).
    var showsAI = false {
        didSet {
            guard showsAI != oldValue else { return }
            aiButton.isHidden = !showsAI
            setNeedsLayout()
        }
    }
    private(set) var suggestions: [Suggestion] = []
    private var theme: KeyboardTheme

    /// The badge text of the current language, or nil to hide the language switch.
    var language: KeyboardLanguage? {
        didSet {
            guard language != oldValue else { return }
            languageButton.isHidden = language == nil
            configureLanguageButton()
            setNeedsLayout()
        }
    }

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
        languageButton.accessibilityIdentifier = "switch-language"
        languageButton.isHidden = true
        languageButton.addTarget(self, action: #selector(languageTapped), for: .touchUpInside)
        addSubview(languageButton)
        actionsButton.accessibilityIdentifier = "keyboard-actions"
        actionsButton.accessibilityLabel = "Aktionen"
        actionsButton.addTarget(self, action: #selector(actionsTapped), for: .touchUpInside)
        addSubview(actionsButton)
        aiButton.isHidden = true
        aiButton.addTarget(self, action: #selector(aiTapped), for: .touchUpInside)
        addSubview(aiButton)
        apply(theme: theme)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        dividers.forEach { $0.backgroundColor = theme.suggestionDivider }
        configureDismissButton()
        configureLanguageButton()
        configureActionsButton()
        aiButton.apply(theme: theme)
        render()
    }

    /// Same capsule as the dismiss button, carrying the language badge.
    private func configureLanguageButton() {
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) {
            config = .glass()
        } else {
            config = .plain()
            config.background.backgroundColor = theme.suggestionHighlight
        }
        config.cornerStyle = .capsule
        config.baseForegroundColor = theme.suggestionText
        config.contentInsets = .zero
        var title = AttributedString(language?.badge ?? "")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        config.attributedTitle = title
        languageButton.configuration = config
        languageButton.tintColor = theme.suggestionText
        languageButton.accessibilityLabel = language.map { "Sprache: \($0.title). Zum Wechseln tippen" }
    }

    /// Same capsule as the dismiss button, with the "⋯" that opens the action menu.
    private func configureActionsButton() {
        let image = UIImage(systemName: "ellipsis",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
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
        actionsButton.configuration = config
        actionsButton.tintColor = theme.suggestionText
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
        let countChanged = new.count != suggestions.count
        suggestions = new
        render()
        if countChanged { setNeedsLayout() }
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
            b.setTitleColor(s?.kind == .ai ? theme.accent : theme.suggestionText, for: .normal)
            b.isHidden = s == nil
            b.accessibilityLabel = s.map { ($0.kind == .ai ? "KI-Vorschlag " : "Vorschlag ") + $0.text }
        }
        let visible = suggestions.count
        dividers[0].isHidden = visible < 2
        dividers[1].isHidden = visible < 3
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let leading = Self.leadingReserved
        let reserved = leading + Self.trailingReserved(hasLanguage: language != nil, hasAI: showsAI)
        // The visible words share the whole strip: one word gets all of it, two get halves. A
        // tap anywhere around a word then reaches it instead of a dead third of the strip.
        let visible = max(min(suggestions.count, buttons.count), 1)
        let w = max(bounds.width - reserved, 0) / CGFloat(visible)
        let inset: CGFloat = 6
        let h = bounds.height - 12
        let buttonHeight = min(h, 32)
        actionsButton.frame = CGRect(x: Self.dismissInset, y: (bounds.height - buttonHeight) / 2,
                                     width: Self.actionsWidth, height: buttonHeight)
        dismissButton.frame = CGRect(x: bounds.width - Self.dismissInset - Self.dismissWidth,
                                     y: (bounds.height - buttonHeight) / 2,
                                     width: Self.dismissWidth, height: buttonHeight)
        languageButton.frame = CGRect(x: dismissButton.frame.minX - Self.dismissInset - Self.languageWidth,
                                      y: (bounds.height - buttonHeight) / 2,
                                      width: Self.languageWidth, height: buttonHeight)
        // Sparkles sit left of the language badge (or of the dismiss button without one).
        let aiRight = language == nil ? dismissButton.frame.minX : languageButton.frame.minX
        aiButton.frame = CGRect(x: aiRight - Self.dismissInset - Self.aiWidth, y: (bounds.height - buttonHeight) / 2,
                                width: Self.aiWidth, height: buttonHeight)
        // The button covers its whole cell (full height, no gaps) so a tap anywhere near the
        // word registers; the pill inside carries the inset look.
        for (i, b) in buttons.enumerated() {
            b.frame = CGRect(x: leading + CGFloat(min(i, visible - 1)) * w, y: 0, width: w, height: bounds.height)
            let pill = pills[i]
            pill.frame = CGRect(x: inset, y: 6, width: max(w - inset * 2, 0), height: max(h, 0))
            pill.layer.cornerRadius = min(max(h, 0) / 2, 12)
        }
        for (i, d) in dividers.enumerated() {
            d.frame = CGRect(x: leading + w * CGFloat(i + 1) - 0.5, y: bounds.height * 0.3, width: 1, height: bounds.height * 0.4)
        }
    }

    @objc private func tapped(_ sender: UIButton) {
        guard suggestions.indices.contains(sender.tag) else { return }
        onSelect?(suggestions[sender.tag])
    }

    @objc private func dismissTapped() { onDismiss?() }

    @objc private func languageTapped() { onLanguage?() }

    @objc private func actionsTapped() { onActions?() }

    @objc private func aiTapped() { onAI?() }

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
