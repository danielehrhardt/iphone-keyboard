import Foundation

/// User preferences shared between the host app and the keyboard extension via the app group.
public final class KeyboardSettings: @unchecked Sendable {

    public static let appGroup = "group.de.codext.umlaut"
    public static let shared = KeyboardSettings(defaults: UserDefaults(suiteName: appGroup) ?? .standard)

    public enum Theme: String, CaseIterable, Sendable, Identifiable {
        case system, light, dark
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .system: return "Automatisch"
            case .light: return "Hell"
            case .dark: return "Dunkel"
            }
        }
    }

    public enum Accent: String, CaseIterable, Sendable, Identifiable {
        case blue, indigo, teal, green, orange, pink, graphite
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .blue: return "Blau"
            case .indigo: return "Indigo"
            case .teal: return "Türkis"
            case .green: return "Grün"
            case .orange: return "Orange"
            case .pink: return "Pink"
            case .graphite: return "Graphit"
            }
        }
        /// sRGB components 0…1.
        public var rgb: (r: Double, g: Double, b: Double) {
            switch self {
            case .blue: return (0.0, 0.478, 1.0)
            case .indigo: return (0.345, 0.337, 0.839)
            case .teal: return (0.188, 0.690, 0.780)
            case .green: return (0.204, 0.780, 0.349)
            case .orange: return (1.0, 0.584, 0.0)
            case .pink: return (1.0, 0.176, 0.333)
            case .graphite: return (0.44, 0.46, 0.50)
            }
        }
    }

    public enum KeySize: String, CaseIterable, Sendable, Identifiable {
        case compact, regular, tall
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .compact: return "Kompakt"
            case .regular: return "Normal"
            case .tall: return "Groß"
            }
        }
        public var heightMultiplier: Double {
            switch self {
            case .compact: return 0.92
            case .regular: return 1.0
            case .tall: return 1.1
            }
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.swipeTyping: true, Keys.autocorrect: true, Keys.autoCapitalize: true,
            Keys.predictions: true, Keys.doubleSpacePeriod: true, Keys.keyPreview: true,
            Keys.haptics: true, Keys.sound: true, Keys.swipeTrail: true, Keys.learnWords: true,
            Keys.theme: Theme.system.rawValue, Keys.accent: Accent.blue.rawValue, Keys.keySize: KeySize.regular.rawValue,
            Keys.longPressNumbers: true, Keys.onboardingDone: false,
        ])
    }

    enum Keys {
        static let swipeTyping = "swipeTyping"
        static let autocorrect = "autocorrect"
        static let autoCapitalize = "autoCapitalize"
        static let predictions = "predictions"
        static let doubleSpacePeriod = "doubleSpacePeriod"
        static let keyPreview = "keyPreview"
        static let haptics = "haptics"
        static let sound = "sound"
        static let swipeTrail = "swipeTrail"
        static let learnWords = "learnWords"
        static let theme = "theme"
        static let accent = "accent"
        static let keySize = "keySize"
        static let longPressNumbers = "longPressNumbers"
        static let onboardingDone = "onboardingDone"
    }

    public var swipeTyping: Bool { get { defaults.bool(forKey: Keys.swipeTyping) } set { defaults.set(newValue, forKey: Keys.swipeTyping) } }
    public var autocorrect: Bool { get { defaults.bool(forKey: Keys.autocorrect) } set { defaults.set(newValue, forKey: Keys.autocorrect) } }
    public var autoCapitalize: Bool { get { defaults.bool(forKey: Keys.autoCapitalize) } set { defaults.set(newValue, forKey: Keys.autoCapitalize) } }
    public var predictions: Bool { get { defaults.bool(forKey: Keys.predictions) } set { defaults.set(newValue, forKey: Keys.predictions) } }
    public var doubleSpacePeriod: Bool { get { defaults.bool(forKey: Keys.doubleSpacePeriod) } set { defaults.set(newValue, forKey: Keys.doubleSpacePeriod) } }
    public var keyPreview: Bool { get { defaults.bool(forKey: Keys.keyPreview) } set { defaults.set(newValue, forKey: Keys.keyPreview) } }
    public var haptics: Bool { get { defaults.bool(forKey: Keys.haptics) } set { defaults.set(newValue, forKey: Keys.haptics) } }
    public var sound: Bool { get { defaults.bool(forKey: Keys.sound) } set { defaults.set(newValue, forKey: Keys.sound) } }
    public var swipeTrail: Bool { get { defaults.bool(forKey: Keys.swipeTrail) } set { defaults.set(newValue, forKey: Keys.swipeTrail) } }
    public var learnWords: Bool { get { defaults.bool(forKey: Keys.learnWords) } set { defaults.set(newValue, forKey: Keys.learnWords) } }
    public var longPressNumbers: Bool { get { defaults.bool(forKey: Keys.longPressNumbers) } set { defaults.set(newValue, forKey: Keys.longPressNumbers) } }
    public var onboardingDone: Bool { get { defaults.bool(forKey: Keys.onboardingDone) } set { defaults.set(newValue, forKey: Keys.onboardingDone) } }

    public var theme: Theme {
        get { Theme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Keys.theme) }
    }
    public var accent: Accent {
        get { Accent(rawValue: defaults.string(forKey: Keys.accent) ?? "") ?? .blue }
        set { defaults.set(newValue.rawValue, forKey: Keys.accent) }
    }
    public var keySize: KeySize {
        get { KeySize(rawValue: defaults.string(forKey: Keys.keySize) ?? "") ?? .regular }
        set { defaults.set(newValue.rawValue, forKey: Keys.keySize) }
    }
}
