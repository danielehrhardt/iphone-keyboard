import UIKit
import AudioToolbox
import KeyboardCore

/// Key clicks and haptics. Both silently do nothing when the system denies them
/// (haptics need "Allow Full Access"; clicks need the extension to be visible).
final class Feedback {
    private let settings: KeyboardSettings
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private var lastHaptic: CFTimeInterval = 0

    init(settings: KeyboardSettings) {
        self.settings = settings
        light.prepare()
    }

    func keyTap() {
        if settings.sound { UIDevice.current.playInputClick() }
        haptic(light, intensity: 0.7)
    }

    func functionTap() {
        if settings.sound { AudioServicesPlaySystemSound(1156) }
        haptic(rigid, intensity: 0.6)
    }

    func deleteTap() {
        if settings.sound { AudioServicesPlaySystemSound(1155) }
        haptic(light, intensity: 0.55)
    }

    func swipeCommit() {
        haptic(rigid, intensity: 0.9)
    }

    func selectionTick() {
        guard settings.haptics else { return }
        selection.selectionChanged()
    }

    private func haptic(_ generator: UIImpactFeedbackGenerator, intensity: CGFloat) {
        guard settings.haptics else { return }
        let now = CACurrentMediaTime()
        guard now - lastHaptic > 0.03 else { return }
        lastHaptic = now
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
    }
}
