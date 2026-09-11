import SwiftUI
import KeyboardCore

/// „Einstellungen“ – every control writes straight through to the shared app-group defaults.
struct SettingsView: View {

    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section("Eingabe") {
                Toggle("Swipe-Eingabe", isOn: $settings.swipeTyping)
                Toggle("Autokorrektur", isOn: $settings.autocorrect)
                Toggle("Wortvorschläge", isOn: $settings.predictions)
                Toggle("Automatische Großschreibung", isOn: $settings.autoCapitalize)
                Toggle("Punkt durch doppeltes Leerzeichen", isOn: $settings.doubleSpacePeriod)
                Toggle("Zahlen durch langes Drücken", isOn: $settings.longPressNumbers)
                Toggle("Neue Wörter lernen", isOn: $settings.learnWords)
            }

            Section {
                Toggle("Justin-Modus", isOn: $settings.justinMode)
            } footer: {
                Text("Jedes getippte oder gewischte Wort wird zu „Justin“ – ohne Ausnahme, in jedem Textfeld.")
            }

            Section("Feedback") {
                Toggle("Tastenvorschau", isOn: $settings.keyPreview)
                Toggle("Wischspur anzeigen", isOn: $settings.swipeTrail)
                Toggle("Haptik", isOn: $settings.haptics)
                Toggle("Tastentöne", isOn: $settings.sound)
            }

            Section("Darstellung") {
                KeyboardPreview(accent: settings.accent,
                                keySize: settings.keySize,
                                scheme: settings.theme.colorScheme,
                                trail: settings.swipeTrail ? .hallo : .none)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                    .animation(.easeInOut(duration: 0.25), value: settings.keySize)

                Picker("Erscheinungsbild", selection: $settings.theme) {
                    ForEach(KeyboardSettings.Theme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                AccentPickerRow(selection: $settings.accent)

                Picker("Tastengröße", selection: $settings.keySize) {
                    ForEach(KeyboardSettings.KeySize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Wörterbuch") {
                NavigationLink {
                    LearnedWordsView()
                } label: {
                    Label("Gelernte Wörter", systemImage: "text.book.closed")
                }
            }

            Section {
                LabeledContent("Version", value: Self.versionString)
            } header: {
                Text("Info")
            } footer: {
                Text("Datenschutz: Umlaut arbeitet vollständig offline. Tastenanschläge, gelernte Wörter und Einstellungen verlassen dein iPhone nie – es gibt weder Server noch Analyse.")
            }
        }
        .navigationTitle("Einstellungen")
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// Horizontal row of accent swatches with a selection ring.
private struct AccentPickerRow: View {
    @Binding var selection: KeyboardSettings.Accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Akzentfarbe")
            HStack(spacing: 0) {
                ForEach(KeyboardSettings.Accent.allCases) { accent in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { selection = accent }
                    } label: {
                        swatch(for: accent)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(accent.title)
                    .accessibilityAddTraits(selection == accent ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func swatch(for accent: KeyboardSettings.Accent) -> some View {
        ZStack {
            Circle()
                .strokeBorder(accent.color, lineWidth: 2)
                .frame(width: 34, height: 34)
                .opacity(selection == accent ? 1 : 0)
            Circle()
                .fill(accent.color)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
        }
        .frame(height: 36)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environmentObject(SettingsStore())
}
