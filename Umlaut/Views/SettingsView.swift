import SwiftUI
import KeyboardCore

/// „Einstellungen“ – every control writes straight through to the shared app-group defaults.
struct SettingsView: View {

    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                ForEach(KeyboardLanguage.allCases) { language in
                    Toggle(isOn: Binding(
                        get: { settings.isEnabled(language) },
                        set: { settings.setEnabled($0, for: language) }
                    )) {
                        HStack(spacing: 10) {
                            Text(language.badge)
                                .font(.caption.weight(.semibold))
                                .monospaced()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text(language.title)
                        }
                    }
                    // The last enabled language stays on: the keyboard always needs one.
                    .disabled(settings.isEnabled(language) && settings.enabledLanguages.count == 1)
                    .accessibilityIdentifier("language-\(language.rawValue)")
                }
            } header: {
                Text("Sprachen")
            } footer: {
                Text(settings.enabledLanguages.count > 1
                     ? "Mit mehreren Sprachen zeigt die Leertaste die aktuelle Sprache, und ein Kürzel neben der Ausblenden-Taste wechselt zur nächsten. Layout, Wörterbuch, Autokorrektur und gelernte Wörter folgen der Sprache."
                     : "Schalte weitere Sprachen ein, um in der Tastatur zwischen ihnen zu wechseln. Layout, Wörterbuch, Autokorrektur und gelernte Wörter folgen der Sprache.")
            }

            if settings.isEnabled(.german) {
                Section {
                    Toggle("Umlaut-Tasten Ü, Ö, Ä", isOn: $settings.germanUmlautKeys)
                        .accessibilityIdentifier("german-umlaut-keys")
                } header: {
                    Text("Deutsche Tastatur")
                } footer: {
                    Text(settings.germanUmlautKeys
                         ? "Ü, Ö und Ä haben eigene Tasten am rechten Rand, wie auf der deutschen Systemtastatur."
                         : "Ohne eigene Umlaut-Tasten sind die Tasten breiter – zehn pro Reihe wie auf der englischen Tastatur. Umlaute erreichst du durch Halten von U, O und A, das ß wie gewohnt auf dem S.")
                }
            }

            Section("Eingabe") {
                Toggle("Swipe-Eingabe", isOn: $settings.swipeTyping)
                Toggle("Autokorrektur", isOn: $settings.autocorrect)
                Toggle("Wortvorschläge", isOn: $settings.predictions)
                Toggle("Automatische Großschreibung", isOn: $settings.autoCapitalize)
                Toggle("Punkt durch doppeltes Leerzeichen", isOn: $settings.doubleSpacePeriod)
                Toggle("Zahlen durch langes Drücken", isOn: $settings.longPressNumbers)
                Toggle("Dynamische Tastenflächen", isOn: $settings.smartHitTargets)
                Toggle("Neue Wörter lernen", isOn: $settings.learnWords)
            }

            Section {
                Toggle("Kommataste neben Leertaste", isOn: $settings.commaKey)
                Toggle("Emoji durch Halten der Kommataste", isOn: $settings.emojiOnCommaKey)
                    .disabled(!settings.commaKey)
            } header: {
                Text("Komma und Emoji")
            } footer: {
                Text("Eine Taste für beides: Tippen schreibt ein Komma, Halten öffnet die Emoji-Tastatur. Ausgeschaltet gibt es eine eigene Emoji-Taste – sie erscheint anstelle der Globus-Taste, wenn keine weitere Tastatur eingerichtet ist.")
            }

            Section {
                Toggle("Justin-Modus", isOn: $settings.justinMode)
            } footer: {
                Text("Jedes getippte oder gewischte Wort wird zu „Justin“ – ohne Ausnahme, in jedem Textfeld.")
            }

            Section {
                Toggle("Tastenvorschau", isOn: $settings.keyPreview)
                Toggle("Wischspur anzeigen", isOn: $settings.swipeTrail)
                Toggle("Haptik", isOn: $settings.haptics)
                Toggle("Tastentöne", isOn: $settings.sound)
            } header: {
                Text("Feedback")
            } footer: {
                Text("Die Tastenvorschau zeigt beim Tippen den gedrückten Buchstaben vergrößert über der Taste.")
            }

            Section("Darstellung") {
                KeyboardPreview(accent: settings.accent,
                                keySize: settings.keySize,
                                scheme: settings.theme.colorScheme,
                                trail: settings.swipeTrail ? .hallo : .none,
                                showsCommaKey: settings.commaKey,
                                emojiOnCommaKey: settings.emojiOnCommaKey,
                                language: settings.currentLanguage,
                                showsLanguageName: settings.enabledLanguages.count > 1,
                                germanUmlautKeys: settings.germanUmlautKeys)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                    .animation(.easeInOut(duration: 0.25), value: settings.keySize)
                    .animation(.easeInOut(duration: 0.25), value: settings.germanUmlautKeys)

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
                Toggle("Zwischenablage merken", isOn: $settings.clipboardHistory)
                    .accessibilityIdentifier("clipboard-history")
                Picker("Aufbewahren", selection: $settings.clipboardRetention) {
                    ForEach(ClipboardRetention.allCases) { retention in
                        Text(retention.title).tag(retention)
                    }
                }
                .disabled(!settings.clipboardHistory)
                NavigationLink {
                    ClipboardHistoryView()
                } label: {
                    Label("Verlauf", systemImage: "doc.on.clipboard")
                }
            } header: {
                Text("Zwischenablage")
            } footer: {
                Text("Kopierte Texte und Bilder erscheinen in der Tastatur hinter der „⋯“-Taste und lassen sich dort wieder einfügen. Bilder legt die Tastatur zurück in die Zwischenablage; eingefügt werden sie wie gewohnt über „Einfügen“. Der Verlauf bleibt auf dem iPhone und wird nach der gewählten Zeit gelöscht. iOS fragt beim ersten Mal, ob Umlaut aus anderen Apps einfügen darf – unter Einstellungen › Umlaut › „Einfügen aus anderen Apps“ lässt sich das dauerhaft erlauben.")
            }

            Section {
                Toggle("Tippverhalten lernen", isOn: $settings.adaptiveTapMap)
                NavigationLink {
                    TapMapView()
                } label: {
                    Label("Deine Tap Map", systemImage: "hand.tap")
                }
            } header: {
                Text("Tap Map")
            } footer: {
                Text("Umlaut merkt sich, wo du auf jeder Taste tatsächlich tippst, und rückt die Trefferflächen unauffällig dorthin – so landen Tipps am Rand einer Taste dort, wo du sie meinst. Gespeichert wird nur die Abweichung pro Taste, nie was du schreibst.")
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
