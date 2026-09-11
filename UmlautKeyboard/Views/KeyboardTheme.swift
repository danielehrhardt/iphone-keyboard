import UIKit
import KeyboardCore

/// Colours and metrics for the keyboard chrome.
///
/// The keyboard itself is transparent: it sits on the system's translucent keyboard material
/// (Liquid Glass on iOS 26), so every colour here is a *translucent* layer on top of that
/// backdrop. Keys read as frosted glass caps, function keys as darker tinted glass, and the
/// user's accent colour drives the swipe trail, the action key and highlights.
struct KeyboardTheme {
    let isDark: Bool
    let accent: UIColor
    /// Opaque stand-in for the system material, only used where no backdrop exists.
    let backdropFallback: UIColor
    let keyBackground: UIColor
    let keyPressedBackground: UIColor
    let functionKeyBackground: UIColor
    let functionKeyPressedBackground: UIColor
    /// Thin bright rim along the top edge of every cap that sells the glass look.
    let keyRim: UIColor
    let keyText: UIColor
    let functionKeyText: UIColor
    let hintText: UIColor
    let keyShadow: UIColor
    let keyShadowOpacity: Float
    let popupBackground: UIColor
    let popupRim: UIColor
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
        let radius: CGFloat = traits.userInterfaceIdiom == .pad ? 10 : 8
        if dark {
            return KeyboardTheme(
                isDark: true, accent: accent,
                backdropFallback: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),
                keyBackground: UIColor(white: 1, alpha: 0.30),
                keyPressedBackground: UIColor(white: 1, alpha: 0.46),
                functionKeyBackground: UIColor(white: 1, alpha: 0.13),
                functionKeyPressedBackground: UIColor(white: 1, alpha: 0.32),
                keyRim: UIColor(white: 1, alpha: 0.16),
                keyText: .white, functionKeyText: .white,
                hintText: UIColor(white: 1, alpha: 0.5),
                keyShadow: .black, keyShadowOpacity: 0.42,
                popupBackground: UIColor(red: 0.36, green: 0.36, blue: 0.39, alpha: 0.98),
                popupRim: UIColor(white: 1, alpha: 0.22),
                suggestionText: .white,
                suggestionDivider: UIColor(white: 1, alpha: 0.16),
                suggestionHighlight: UIColor(white: 1, alpha: 0.14),
                cornerRadius: radius)
        } else {
            return KeyboardTheme(
                isDark: false, accent: accent,
                backdropFallback: UIColor(red: 0.82, green: 0.835, blue: 0.86, alpha: 1),
                keyBackground: UIColor(white: 1, alpha: 0.94),
                keyPressedBackground: UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 0.96),
                functionKeyBackground: UIColor(red: 0.56, green: 0.60, blue: 0.66, alpha: 0.42),
                functionKeyPressedBackground: UIColor(white: 1, alpha: 0.94),
                keyRim: UIColor(white: 1, alpha: 0.75),
                keyText: .black, functionKeyText: .black,
                hintText: UIColor(white: 0, alpha: 0.42),
                keyShadow: UIColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1), keyShadowOpacity: 0.30,
                popupBackground: UIColor(white: 1, alpha: 0.98),
                popupRim: UIColor(white: 1, alpha: 0.9),
                suggestionText: .black,
                suggestionDivider: UIColor(white: 0, alpha: 0.16),
                suggestionHighlight: UIColor(white: 0, alpha: 0.08),
                cornerRadius: radius)
        }
    }

    /// Text colour on top of the accent colour.
    var onAccent: UIColor { .white }

    /// Slightly brighter accent for the pressed state of accent-filled keys.
    var accentPressed: UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
        guard accent.getHue(&h, saturation: &s, brightness: &b, alpha: &al) else { return accent }
        return UIColor(hue: h, saturation: max(0, s - 0.12), brightness: min(1, b + 0.12), alpha: al)
    }

    /// The `UIUserInterfaceStyle` the system backdrop should render in for the chosen theme.
    static func interfaceStyle(for settings: KeyboardSettings) -> UIUserInterfaceStyle {
        switch settings.theme {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Row heights for the different environments; the total keyboard height is keys + suggestion bar
/// (+ the bottom safe area, which the owner adds so the home indicator gets its own strip).
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
