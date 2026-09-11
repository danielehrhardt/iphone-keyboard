import UIKit
import KeyboardCore

/// Root view of the extension: suggestion strip on top, key grid below, emoji panel as an overlay.
///
/// The view is transparent so the system's keyboard material shows through, and it respects the
/// safe area: keys stay above the home indicator and clear of the notch in landscape.
final class KeyboardView: UIView {
    let suggestionBar: SuggestionBarView
    let grid: KeyGridView
    /// Created on first use: the colour-emoji font and collection view cost tens of MB.
    private(set) var emojiPanel: EmojiPanelView?
    weak var emojiDelegate: EmojiPanelDelegate?
    private(set) var theme: KeyboardTheme
    var suggestionHeight: CGFloat = 44 { didSet { setNeedsLayout() } }
    /// Called after every layout pass so the owner can (re)build the key grid for the new size.
    var onLayout: (() -> Void)?
    var isEmojiVisible = false {
        didSet {
            if isEmojiVisible, emojiPanel == nil {
                let panel = EmojiPanelView(theme: theme)
                panel.delegate = emojiDelegate
                panel.frame = bounds
                addSubview(panel)
                emojiPanel = panel
            }
            emojiPanel?.isHidden = !isEmojiVisible
            grid.isHidden = isEmojiVisible
            suggestionBar.isHidden = isEmojiVisible
            if isEmojiVisible { emojiPanel?.refreshRecents() }
        }
    }

    init(theme: KeyboardTheme, feedback: Feedback) {
        self.theme = theme
        suggestionBar = SuggestionBarView(theme: theme)
        grid = KeyGridView(theme: theme, feedback: feedback)
        super.init(frame: .zero)
        clipsToBounds = false
        backgroundColor = .clear
        addSubview(suggestionBar)
        addSubview(grid)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        suggestionBar.apply(theme: theme)
        grid.apply(theme: theme)
        emojiPanel?.apply(theme: theme)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let insets = safeAreaInsets
        let x = insets.left
        let width = max(0, bounds.width - insets.left - insets.right)
        let gridHeight = max(0, bounds.height - suggestionHeight - insets.bottom)
        suggestionBar.frame = CGRect(x: x, y: 0, width: width, height: suggestionHeight)
        grid.frame = CGRect(x: x, y: suggestionHeight, width: width, height: gridHeight)
        emojiPanel?.frame = bounds
        onLayout?()
    }
}
