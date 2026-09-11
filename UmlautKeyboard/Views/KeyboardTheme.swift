import UIKit
import KeyboardCore

/// Colours and metrics for the keyboard chrome. Derived from the system look so it feels native,
/// with the user's accent colour used for the swipe trail, the action key and highlights.
struct KeyboardTheme {
    let isDark: Bool
    let accent: UIColor
    let background: UIColor
    let keyBackground: UIColor
    let keyPressedBackground: UIColor
    let functionKeyBackground: UIColor
    let functionKeyPressedBackground: UIColor
    let keyText: UIColor
    let functionKeyText: UIColor
    let hintText: UIColor
    let keyShadow: UIColor
    let popupBackground: UIColor
    let suggestionText: UIColor
    let suggestionDivider: UIColor
    let suggestionHighlight: UIColor
    let cornerRadius: CGFloat

    static func current(traits: UITraitCollection, settings: KeyboardSettings) -> KeyboardTheme {
        let dark: Bool
        switch settings.theme {
        case .system: dark = traits.userInterfaceStyle == .dark
        case .light: dark = false
        case .dark: dark = true
        }
        let a = settings.accent.rgb
        let accent = UIColor(red: a.r, green: a.g, blue: a.b, alpha: 1)
        let radius: CGFloat = traits.userInterfaceIdiom == .pad ? 8 : 6
        if dark {
            return KeyboardTheme(
                isDark: true, accent: accent,
                background: UIColor(white: 0.16, alpha: 1),
                keyBackground: UIColor(white: 0.42, alpha: 1),
                keyPressedBackground: UIColor(white: 0.55, alpha: 1),
                functionKeyBackground: UIColor(white: 0.27, alpha: 1),
                functionKeyPressedBackground: UIColor(white: 0.42, alpha: 1),
                keyText: .white, functionKeyText: .white,
                hintText: UIColor(white: 1, alpha: 0.55),
                keyShadow: UIColor.black.withAlphaComponent(0.55),
                popupBackground: UIColor(white: 0.46, alpha: 1),
                suggestionText: .white,
                suggestionDivider: UIColor(white: 1, alpha: 0.18),
                suggestionHighlight: UIColor(white: 1, alpha: 0.12),
                cornerRadius: radius)
        } else {
            return KeyboardTheme(
                isDark: false, accent: accent,
                background: UIColor(red: 0.820, green: 0.835, blue: 0.858, alpha: 1),
                keyBackground: .white,
                keyPressedBackground: UIColor(white: 0.93, alpha: 1),
                functionKeyBackground: UIColor(red: 0.675, green: 0.698, blue: 0.741, alpha: 1),
                functionKeyPressedBackground: .white,
                keyText: .black, functionKeyText: .black,
                hintText: UIColor(white: 0, alpha: 0.45),
                keyShadow: UIColor(red: 0.53, green: 0.54, blue: 0.56, alpha: 1),
                popupBackground: .white,
                suggestionText: .black,
                suggestionDivider: UIColor(white: 0, alpha: 0.18),
                suggestionHighlight: UIColor(white: 0, alpha: 0.07),
                cornerRadius: radius)
        }
    }

    /// Text colour on top of the accent colour.
    var onAccent: UIColor { .white }
}

/// Row heights for the different environments; the total keyboard height is keys + suggestion bar.
enum KeyboardMetrics {
    static func heights(for traits: UITraitCollection, screenSize: CGSize, keySize: KeyboardSettings.KeySize) -> (keys: CGFloat, suggestions: CGFloat) {
        let landscape = screenSize.width > screenSize.height
        var keys: CGFloat
        var bar: CGFloat
        if traits.userInterfaceIdiom == .pad {
            keys = landscape ? 300 : 264
            bar = 50
        } else if landscape {
            keys = 162
            bar = 38
        } else {
            keys = screenSize.height >= 800 ? 216 : 206
            bar = 44
        }
        keys *= keySize.heightMultiplier
        return (keys.rounded(), bar)
    }

    static func layoutMetrics(for traits: UITraitCollection, screenSize: CGSize) -> KeyboardGeometry.Metrics {
        if traits.userInterfaceIdiom == .pad { return .pad }
        return screenSize.width > screenSize.height ? .phoneLandscape : .phonePortrait
    }
}
