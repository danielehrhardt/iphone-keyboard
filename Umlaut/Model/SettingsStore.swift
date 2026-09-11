import Combine
import Foundation
import UIKit
import KeyboardCore

/// Observable mirror of `KeyboardSettings`. Every change is written straight through to the
/// shared app-group defaults so the keyboard extension picks it up on its next appearance.
@MainActor
final class SettingsStore: ObservableObject {

    private static let extensionBundleID = "de.codext.umlaut.keyboard"
    private static let fullAccessKey = "fullAccessConfirmed"
    private static let installedKeyboardsKey = "AppleKeyboards"

    private let settings = KeyboardSettings.shared
    private let groupDefaults = UserDefaults(suiteName: KeyboardSettings.appGroup) ?? .standard
    private var isReloading = false

    // MARK: Eingabe

    @Published var swipeTyping = true { didSet { write { settings.swipeTyping = swipeTyping } } }
    @Published var autocorrect = true { didSet { write { settings.autocorrect = autocorrect } } }
    @Published var predictions = true { didSet { write { settings.predictions = predictions } } }
    @Published var autoCapitalize = true { didSet { write { settings.autoCapitalize = autoCapitalize } } }
    @Published var doubleSpacePeriod = true { didSet { write { settings.doubleSpacePeriod = doubleSpacePeriod } } }
    @Published var longPressNumbers = true { didSet { write { settings.longPressNumbers = longPressNumbers } } }
    @Published var learnWords = true { didSet { write { settings.learnWords = learnWords } } }

    // MARK: Feedback

    @Published var keyPreview = true { didSet { write { settings.keyPreview = keyPreview } } }
    @Published var swipeTrail = true { didSet { write { settings.swipeTrail = swipeTrail } } }
    @Published var haptics = true { didSet { write { settings.haptics = haptics } } }
    @Published var sound = true { didSet { write { settings.sound = sound } } }

    // MARK: Darstellung

    @Published var theme: KeyboardSettings.Theme = .system { didSet { write { settings.theme = theme } } }
    @Published var accent: KeyboardSettings.Accent = .blue { didSet { write { settings.accent = accent } } }
    @Published var keySize: KeyboardSettings.KeySize = .regular { didSet { write { settings.keySize = keySize } } }

    // MARK: Einrichtung

    @Published var onboardingDone = false { didSet { write { settings.onboardingDone = onboardingDone } } }
    @Published var fullAccessConfirmed = false {
        didSet { write { groupDefaults.set(fullAccessConfirmed, forKey: Self.fullAccessKey) } }
    }
    /// True once „Umlaut“ appears in the list of installed keyboards.
    @Published private(set) var keyboardEnabled = false

    init() {
        reload()
    }

    /// Pulls every value back out of the shared defaults (the keyboard may have changed them).
    func reload() {
        isReloading = true
        swipeTyping = settings.swipeTyping
        autocorrect = settings.autocorrect
        predictions = settings.predictions
        autoCapitalize = settings.autoCapitalize
        doubleSpacePeriod = settings.doubleSpacePeriod
        longPressNumbers = settings.longPressNumbers
        learnWords = settings.learnWords
        keyPreview = settings.keyPreview
        swipeTrail = settings.swipeTrail
        haptics = settings.haptics
        sound = settings.sound
        theme = settings.theme
        accent = settings.accent
        keySize = settings.keySize
        onboardingDone = settings.onboardingDone
        fullAccessConfirmed = groupDefaults.bool(forKey: Self.fullAccessKey)
        isReloading = false
        refreshKeyboardStatus()
    }

    func refreshKeyboardStatus() {
        let installed = UserDefaults.standard.object(forKey: Self.installedKeyboardsKey) as? [String] ?? []
        let enabled = installed.contains { $0.contains(Self.extensionBundleID) }
        if enabled != keyboardEnabled { keyboardEnabled = enabled }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func write(_ body: () -> Void) {
        guard !isReloading else { return }
        body()
    }
}
