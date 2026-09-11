import SwiftUI
import KeyboardCore

extension KeyboardSettings.Accent {
    /// SwiftUI colour for the accent stored in the shared settings.
    var color: Color {
        let c = rgb
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }
}

extension KeyboardSettings.Theme {
    /// `nil` means "follow the system".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
