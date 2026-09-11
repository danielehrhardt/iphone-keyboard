import UIKit
import KeyboardCore

/// Root view of the extension: suggestion strip on top, key grid below, emoji panel as an overlay.
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
        backgroundColor = theme.background
        addSubview(suggestionBar)
        addSubview(grid)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        backgroundColor = theme.background
        suggestionBar.apply(theme: theme)
        grid.apply(theme: theme)
        emojiPanel?.apply(theme: theme)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        suggestionBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: suggestionHeight)
        grid.frame = CGRect(x: 0, y: suggestionHeight, width: bounds.width, height: bounds.height - suggestionHeight)
        emojiPanel?.frame = bounds
        onLayout?()
    }
}
