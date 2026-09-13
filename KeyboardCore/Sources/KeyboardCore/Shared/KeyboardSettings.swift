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
            Keys.longPressNumbers: true, Keys.commaKey: true, Keys.emojiOnCommaKey: true, Keys.smartHitTargets: true, Keys.adaptiveTapMap: true, Keys.justinMode: false, Keys.onboardingDone: false,
            Keys.germanUmlautKeys: true,
            Keys.clipboardHistory: true, Keys.clipboardRetention: ClipboardRetention.day.rawValue,
            Keys.enabledLanguages: [KeyboardLanguage.default.rawValue], Keys.currentLanguage: KeyboardLanguage.default.rawValue,
        ])
    }

    enum Keys {
        static let enabledLanguages = "enabledLanguages"
        static let currentLanguage = "currentLanguage"
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
        static let commaKey = "commaKey"
        static let emojiOnCommaKey = "emojiOnCommaKey"
        static let smartHitTargets = "smartHitTargets"
        static let adaptiveTapMap = "adaptiveTapMap"
        static let justinMode = "justinMode"
        static let onboardingDone = "onboardingDone"
        static let germanUmlautKeys = "germanUmlautKeys"
        static let clipboardHistory = "clipboardHistory"
        static let clipboardRetention = "clipboardRetention"
        static let clipboardChangeCount = "clipboardChangeCount"
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
    /// Shows a comma key left of the space bar.
    public var commaKey: Bool { get { defaults.bool(forKey: Keys.commaKey) } set { defaults.set(newValue, forKey: Keys.commaKey) } }
    /// One key for both: tapping the comma key types ",", holding it opens the emoji picker.
    /// Off shows a separate emoji key instead (where the bottom row has room for one).
    public var emojiOnCommaKey: Bool { get { defaults.bool(forKey: Keys.emojiOnCommaKey) } set { defaults.set(newValue, forKey: Keys.emojiOnCommaKey) } }
    /// Letter keys grow their touch area towards likely next letters (like the system keyboard).
    public var smartHitTargets: Bool { get { defaults.bool(forKey: Keys.smartHitTargets) } set { defaults.set(newValue, forKey: Keys.smartHitTargets) } }
    /// The keyboard learns where this user's fingers land on each letter key and shifts the hit
    /// targets accordingly (see `TapMap`).
    public var adaptiveTapMap: Bool { get { defaults.bool(forKey: Keys.adaptiveTapMap) } set { defaults.set(newValue, forKey: Keys.adaptiveTapMap) } }
    /// Every typed or swiped word is replaced by „Justin“.
    public var justinMode: Bool { get { defaults.bool(forKey: Keys.justinMode) } set { defaults.set(newValue, forKey: Keys.justinMode) } }
    public var onboardingDone: Bool { get { defaults.bool(forKey: Keys.onboardingDone) } set { defaults.set(newValue, forKey: Keys.onboardingDone) } }
    /// The German layout shows ü/ö/ä as keys of their own. Off, it has ten keys per row like the
    /// English one and the umlauts are reached by holding u/o/a (ß stays on s).
    public var germanUmlautKeys: Bool { get { defaults.bool(forKey: Keys.germanUmlautKeys) } set { defaults.set(newValue, forKey: Keys.germanUmlautKeys) } }

    // MARK: Clipboard

    /// The keyboard remembers what was copied (text and images) and offers it again from its
    /// action menu. Needs "Full Access", like everything else the extension shares with the app.
    public var clipboardHistory: Bool { get { defaults.bool(forKey: Keys.clipboardHistory) } set { defaults.set(newValue, forKey: Keys.clipboardHistory) } }
    /// How long copied items are kept.
    public var clipboardRetention: ClipboardRetention {
        get { ClipboardRetention(rawValue: defaults.string(forKey: Keys.clipboardRetention) ?? "") ?? .day }
        set { defaults.set(newValue.rawValue, forKey: Keys.clipboardRetention) }
    }
    /// `UIPasteboard.changeCount` of the last clip either process captured, so the app and the
    /// keyboard never read the same clip twice (reading shows the system's paste banner).
    public var clipboardChangeCount: Int { get { defaults.integer(forKey: Keys.clipboardChangeCount) } set { defaults.set(newValue, forKey: Keys.clipboardChangeCount) } }

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

    // MARK: Languages

    /// The languages the keyboard switches between, in the order they are cycled. Never empty:
    /// an empty or unknown list falls back to the default language.
    public var enabledLanguages: [KeyboardLanguage] {
        get {
            let stored = defaults.stringArray(forKey: Keys.enabledLanguages) ?? []
            var seen = Set<KeyboardLanguage>()
            let languages = stored.compactMap(KeyboardLanguage.init(rawValue:)).filter { seen.insert($0).inserted }
            return languages.isEmpty ? [.default] : languages
        }
        set {
            var seen = Set<KeyboardLanguage>()
            let languages = newValue.filter { seen.insert($0).inserted }
            defaults.set((languages.isEmpty ? [.default] : languages).map(\.rawValue), forKey: Keys.enabledLanguages)
        }
    }

    /// The language the keyboard is typing in. Always one of `enabledLanguages`: a language that
    /// was switched off in the app falls back to the first enabled one.
    public var currentLanguage: KeyboardLanguage {
        get {
            let enabled = enabledLanguages
            guard let stored = defaults.string(forKey: Keys.currentLanguage).flatMap(KeyboardLanguage.init(rawValue:)),
                  enabled.contains(stored) else { return enabled[0] }
            return stored
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.currentLanguage) }
    }

    /// Whether the keyboard offers a way to switch languages (two or more enabled).
    public var hasMultipleLanguages: Bool { enabledLanguages.count > 1 }

    /// The language after the current one in the enabled list, wrapping around.
    public func nextLanguage(after language: KeyboardLanguage) -> KeyboardLanguage {
        let enabled = enabledLanguages
        guard let i = enabled.firstIndex(of: language) else { return enabled[0] }
        return enabled[(i + 1) % enabled.count]
    }

    /// Switches a language on or off, keeping at least one enabled and the current language valid.
    public func setLanguage(_ language: KeyboardLanguage, enabled: Bool) {
        var languages = enabledLanguages
        if enabled {
            if !languages.contains(language) { languages.append(language) }
        } else {
            guard languages.count > 1 else { return }
            languages.removeAll { $0 == language }
        }
        enabledLanguages = languages
        // The getter already falls back; this clears the stale value out of the defaults.
        if let stored = defaults.string(forKey: Keys.currentLanguage).flatMap(KeyboardLanguage.init(rawValue:)),
           !languages.contains(stored) {
            currentLanguage = languages[0]
        }
    }
}
