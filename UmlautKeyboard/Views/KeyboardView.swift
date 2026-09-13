import UIKit
import KeyboardCore

/// Root view of the extension: suggestion strip on top, key grid below, emoji panel and
/// clipboard panel as overlays, the action menu as a dropdown over the grid.
///
/// The view is transparent so the system's keyboard material shows through, and it respects the
/// safe area: keys stay above the home indicator and clear of the notch in landscape.
final class KeyboardView: UIView {
    let suggestionBar: SuggestionBarView
    let grid: KeyGridView
    /// Created on first use: the colour-emoji font and collection view cost tens of MB.
    private(set) var emojiPanel: EmojiPanelView?
    weak var emojiDelegate: EmojiPanelDelegate?
    /// Created on first use, like the emoji panel.
    private(set) var clipboardPanel: ClipboardPanelView?
    weak var clipboardDelegate: ClipboardPanelDelegate?
    /// The AI panel (strip button ✦); created on first use, like the emoji panel.
    private(set) var aiPanel: AIPanelView?
    weak var aiDelegate: AIPanelDelegate?
    /// The dropdown under the strip's "⋯" button; created on first use.
    private(set) var actionMenu: ActionMenuView?
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
            if isEmojiVisible { isClipboardVisible = false; isActionMenuVisible = false; isAIVisible = false }
            emojiPanel?.isHidden = !isEmojiVisible
            updateOverlayVisibility()
            if isEmojiVisible { emojiPanel?.refreshRecents() }
        }
    }
    var isClipboardVisible = false {
        didSet {
            if isClipboardVisible, clipboardPanel == nil {
                let panel = ClipboardPanelView(theme: theme)
                panel.delegate = clipboardDelegate
                panel.frame = bounds
                addSubview(panel)
                clipboardPanel = panel
            }
            if isClipboardVisible { isEmojiVisible = false; isActionMenuVisible = false; isAIVisible = false }
            clipboardPanel?.isHidden = !isClipboardVisible
            updateOverlayVisibility()
        }
    }
    var isAIVisible = false {
        didSet {
            if isAIVisible, aiPanel == nil {
                let panel = AIPanelView(theme: theme, tone: .neutral, target: .english)
                panel.delegate = aiDelegate
                panel.frame = bounds
                addSubview(panel)
                aiPanel = panel
            }
            if isAIVisible { isEmojiVisible = false; isClipboardVisible = false; isActionMenuVisible = false }
            aiPanel?.isHidden = !isAIVisible
            updateOverlayVisibility()
        }
    }
    /// Shows or hides the action dropdown. `actions` is set by the owner before opening.
    var isActionMenuVisible = false {
        didSet {
            guard isActionMenuVisible != oldValue else { return }
            if isActionMenuVisible, actionMenu == nil {
                let menu = ActionMenuView(theme: theme)
                menu.frame = bounds
                addSubview(menu)
                actionMenu = menu
            }
            if let menu = actionMenu {
                bringSubviewToFront(menu)
                menu.isHidden = !isActionMenuVisible
                if isActionMenuVisible {
                    menu.alpha = 0
                    menu.transform = CGAffineTransform(translationX: 0, y: -6)
                    UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                        menu.alpha = 1
                        menu.transform = .identity
                    }
                }
            }
        }
    }

    /// The grid and the strip only show while no panel covers them.
    private func updateOverlayVisibility() {
        let covered = isEmojiVisible || isClipboardVisible || isAIVisible
        grid.isHidden = covered
        suggestionBar.isHidden = covered
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
        clipboardPanel?.apply(theme: theme)
        aiPanel?.apply(theme: theme)
        actionMenu?.apply(theme: theme)
    }

    /// Every touch from the grid's top edge down belongs to the key grid, including the strip
    /// below the bottom row (the home-indicator inset) and the side insets: a thumb that lands a
    /// little low on the space bar, as thumbs do when typing fast, must reach the nearest key
    /// rather than a dead zone. The suggestion bar and the emoji panel keep their own areas.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha >= 0.01, self.point(inside: point, with: event) else { return nil }
        // While the dropdown is open it owns every touch (its backdrop closes it).
        if let menu = actionMenu, !menu.isHidden { return menu.hitTest(convert(point, to: menu), with: event) ?? menu }
        if let panel = emojiPanel, !panel.isHidden { return super.hitTest(point, with: event) }
        if let panel = clipboardPanel, !panel.isHidden { return super.hitTest(point, with: event) }
        if let panel = aiPanel, !panel.isHidden { return super.hitTest(point, with: event) }
        if !grid.isHidden, grid.isUserInteractionEnabled, grid.alpha >= 0.01, point.y >= grid.frame.minY {
            return grid
        }
        return super.hitTest(point, with: event)
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
        clipboardPanel?.frame = bounds
        aiPanel?.frame = bounds
        actionMenu?.frame = bounds
        // The card hangs from the "⋯" button.
        actionMenu?.anchor = CGPoint(x: x + SuggestionBarView.dismissInset, y: suggestionHeight - 4)
        onLayout?()
    }
}
