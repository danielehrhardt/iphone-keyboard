import SwiftUI
import KeyboardCore

/// „Umlaut AI“ – keys per provider, the default model, one model per feature and the two
/// passive features. Everything writes straight through to the shared defaults and keychain.
struct AISettingsView: View {

    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                hero
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Toggle("KI-Funktionen", isOn: $settings.aiEnabled)
                    .accessibilityIdentifier("ai-enabled")
            } footer: {
                Text("Zeigt in der Tastatur den ✦-Knopf neben Sprach- und Ausblenden-Taste. Die KI bearbeitet die Auswahl oder den Text vor dem Cursor.")
            }

            Section {
                ForEach(AIProvider.allCases) { provider in
                    NavigationLink {
                        AIProviderKeyView(provider: provider)
                    } label: {
                        providerRow(provider)
                    }
                    .accessibilityIdentifier("ai-provider-\(provider.rawValue)")
                }
            } header: {
                Text("Anbieter")
            } footer: {
                Text("Du brauchst mindestens einen API-Schlüssel. Er wird im Schlüsselbund gespeichert und nur an den jeweiligen Anbieter geschickt.")
            }

            Section {
                NavigationLink {
                    AIModelPickerView(title: "Standardmodell", selection: $settings.aiDefaultModel, allowsDefault: false)
                } label: {
                    LabeledContent("Standardmodell", value: settings.aiDefaultModel?.title ?? "Wählen")
                }
                .disabled(settings.aiConfiguredProviders.isEmpty)
                .accessibilityIdentifier("ai-default-model")
            } header: {
                Text("Modell")
            } footer: {
                Text(settings.aiConfiguredProviders.isEmpty
                     ? "Hinterlege zuerst einen Schlüssel."
                     : "Gilt für alle Funktionen ohne eigenes Modell.")
            }

            Section {
                ForEach(AIFeature.allCases) { feature in
                    NavigationLink {
                        AIModelPickerView(title: feature.title,
                                          selection: Binding(get: { settings.aiFeatureModels[feature] },
                                                             set: { settings.setAIModel($0, for: feature) }),
                                          allowsDefault: true)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: feature.symbol)
                                .font(.body.weight(.medium))
                                .foregroundStyle(settings.accent.color)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                Text(feature.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(settings.aiFeatureModels[feature]?.title ?? "Standard")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(settings.aiConfiguredProviders.isEmpty)
                }
            } header: {
                Text("Funktionen")
            } footer: {
                Text("Für „Korrigieren“ und „Weiterschreiben“ lohnt sich ein schnelles Modell, für „Umformulieren“ und „Antworten“ ein starkes.")
            }

            Section {
                Toggle("Sätze im Hintergrund prüfen", isOn: $settings.aiAutocorrect)
                    .accessibilityIdentifier("ai-autocorrect")
                Toggle("KI-Vorschläge in der Leiste", isOn: $settings.aiSuggestions)
                    .accessibilityIdentifier("ai-suggestions")
            } header: {
                Text("Beim Tippen")
            } footer: {
                Text("Satzprüfung: Sobald du einen Satz beendest, prüft ihn das Modell für „Korrigieren“; eine Korrektur erscheint mit ✦ in der Vorschlagsleiste und wird erst durch Tippen übernommen. Vorschläge: Nach einer kurzen Pause am Wortende schlägt das Modell für „Weiterschreiben“ vor, wie es weitergeht. Beides kostet Anfragen bei deinem Anbieter.")
            }
            .disabled(!settings.aiEnabled)

            Section {
                EmptyView()
            } footer: {
                Text("Datenschutz: Nur der Text, den du bearbeiten lässt (bzw. der geprüfte Satz), geht an den gewählten Anbieter. Es gibt keinen Umlaut-Server dazwischen.")
            }
        }
        .navigationTitle("Umlaut AI")
        .onAppear { settings.refreshAIKeys() }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            AISparkleIcon(size: 56)
                .shadow(color: settings.accent.color.opacity(0.35), radius: 14, y: 6)
            Text("Schreiben mit KI, direkt in der Tastatur")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Wähle einen Anbieter, hinterlege deinen Schlüssel, such dir ein Modell aus – mehr ist es nicht.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func providerRow(_ provider: AIProvider) -> some View {
        let configured = settings.aiConfiguredProviders.contains(provider)
        return HStack(spacing: 12) {
            AIProviderMark(provider: provider)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.title)
                Text(provider.family)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if configured {
                Label("Schlüssel", systemImage: "checkmark.seal.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Schlüssel hinterlegt")
            } else {
                Text("Kein Schlüssel")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// The ✦ badge in an accent gradient, shared by the settings row and the hero.
struct AISparkleIcon: View {
    var size: CGFloat = 30
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        let accent = settings.accent.color
        return RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [accent.opacity(0.85), accent, .indigo],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// A two-letter mark per provider, tinted per family.
struct AIProviderMark: View {
    let provider: AIProvider

    private var letters: String {
        switch provider {
        case .anthropic: return "A"
        case .openai: return "O"
        case .google: return "G"
        }
    }

    private var color: Color {
        switch provider {
        case .anthropic: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .openai: return Color(red: 0.06, green: 0.63, blue: 0.52)
        case .google: return Color(red: 0.26, green: 0.52, blue: 0.96)
        }
    }

    var body: some View {
        Text(letters)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Key entry

/// One provider's key: enter or paste it, test it, remove it.
struct AIProviderKeyView: View {
    let provider: AIProvider

    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openURL) private var openURL
    @State private var key = ""
    @State private var reveal = false
    @State private var test: TestState = .idle
    @FocusState private var focused: Bool

    private enum TestState: Equatable {
        case idle, running, ok(String), failed(String)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Group {
                        if reveal {
                            TextField(provider.keyHint, text: $key)
                        } else {
                            SecureField(provider.keyHint, text: $key)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($focused)
                    .accessibilityIdentifier("ai-key-field")
                    .onChange(of: key) { _, _ in test = .idle }
                    Button {
                        reveal.toggle()
                    } label: {
                        Image(systemName: reveal ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(reveal ? "Schlüssel verbergen" : "Schlüssel anzeigen")
                }
                Button {
                    if let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !pasted.isEmpty {
                        key = pasted
                    }
                } label: {
                    Label("Aus der Zwischenablage einfügen", systemImage: "doc.on.clipboard")
                }
            } header: {
                Text("API-Schlüssel")
            } footer: {
                if !key.isEmpty, !provider.looksLikeKey(key) {
                    Text("Das sieht nicht nach einem \(provider.title)-Schlüssel aus (üblich: \(provider.keyHint)). Speichern geht trotzdem.")
                } else {
                    Text("Wird beim Verlassen gespeichert – im Schlüsselbund, geteilt nur mit der Tastatur.")
                }
            }

            Section {
                Button {
                    runTest()
                } label: {
                    HStack {
                        Label("Verbindung testen", systemImage: "bolt.horizontal")
                        Spacer()
                        switch test {
                        case .idle: EmptyView()
                        case .running: ProgressView()
                        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        }
                    }
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || test == .running)
                .accessibilityIdentifier("ai-key-test")
            } footer: {
                switch test {
                case .idle: Text("Schickt eine winzige Anfrage an \(provider.defaultModel.title).")
                case .running: Text("Fragt \(provider.defaultModel.title)…")
                case .ok(let m): Text(m)
                case .failed(let m): Text(m).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    openURL(provider.keyConsoleURL)
                } label: {
                    Label("Schlüssel bei \(provider.title) erstellen", systemImage: "arrow.up.forward.app")
                }
            } footer: {
                Text(provider.keyConsoleURL.absoluteString)
            }

            if settings.aiConfiguredProviders.contains(provider) {
                Section {
                    Button(role: .destructive) {
                        key = ""
                        settings.setAIKey(nil, for: provider)
                    } label: {
                        Label("Schlüssel entfernen", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(provider.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { key = settings.aiKey(for: provider) ?? "" }
        .onDisappear { save() }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button("Fertig") { focused = false; save() }
            }
        }
    }

    private func save() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (settings.aiKey(for: provider) ?? "") else { return }
        settings.setAIKey(trimmed.isEmpty ? nil : trimmed, for: provider)
    }

    private func runTest() {
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
        test = .running
        Task {
            do {
                try await AIClient.shared.verify(model: provider.defaultModel, apiKey: candidate)
                test = .ok("Funktioniert – \(provider.defaultModel.title) hat geantwortet.")
                save()
            } catch {
                test = .failed((error as? AIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}

// MARK: - Model picker

/// All models of every configured provider, with a custom ID per provider. `allowsDefault`
/// adds the "Standardmodell" row for a feature's override.
struct AIModelPickerView: View {
    let title: String
    @Binding var selection: AIModel?
    var allowsDefault: Bool

    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var customProvider: AIProvider?
    @State private var customID = ""

    var body: some View {
        List {
            if allowsDefault {
                Section {
                    row(title: "Standardmodell", subtitle: settings.aiDefaultModel?.title ?? "Nicht gewählt", tier: nil, selected: selection == nil) {
                        selection = nil
                        dismiss()
                    }
                }
            }
            ForEach(AIProvider.allCases) { provider in
                let configured = settings.aiConfiguredProviders.contains(provider)
                Section {
                    ForEach(provider.models) { model in
                        row(title: model.title, subtitle: model.modelID, tier: model.tier, selected: selection == model) {
                            selection = model
                            dismiss()
                        }
                        .disabled(!configured)
                    }
                    if let custom = selection, custom.provider == provider, custom.isCustom {
                        row(title: custom.title, subtitle: "Eigene Modell-ID", tier: nil, selected: true) {}
                    }
                    Button {
                        customProvider = provider
                        customID = ""
                    } label: {
                        Label("Eigene Modell-ID…", systemImage: "plus.circle")
                    }
                    .disabled(!configured)
                } header: {
                    Text(provider.title)
                } footer: {
                    if !configured { Text("Kein Schlüssel für \(provider.title) hinterlegt.") }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Eigene Modell-ID", isPresented: Binding(get: { customProvider != nil }, set: { if !$0 { customProvider = nil } })) {
            TextField("z. B. \(customProvider?.defaultModel.modelID ?? "")", text: $customID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Verwenden") {
                if let provider = customProvider, !customID.trimmingCharacters(in: .whitespaces).isEmpty {
                    selection = provider.model(withID: customID.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Modell-ID genau so, wie der Anbieter sie in seiner API erwartet.")
        }
    }

    private func row(title: String, subtitle: String, tier: AIModel.Tier?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let tier {
                    Text(tier.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tierColor(tier).opacity(0.15), in: Capsule())
                        .foregroundStyle(tierColor(tier))
                }
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(settings.accent.color)
                    .opacity(selected ? 1 : 0)
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tierColor(_ tier: AIModel.Tier) -> Color {
        switch tier {
        case .flagship: return .purple
        case .balanced: return .blue
        case .fast: return .green
        }
    }
}

#Preview {
    NavigationStack { AISettingsView() }
        .environmentObject(SettingsStore())
}
