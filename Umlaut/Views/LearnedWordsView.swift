import SwiftUI
import KeyboardCore

/// „Gelernte Wörter“ – the personal dictionary shared with the keyboard extension.
struct LearnedWordsView: View {

    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var store = LexiconStore()
    @Environment(\.scenePhase) private var scenePhase

    @State private var newWord = ""
    @State private var isConfirmingDeleteAll = false
    @FocusState private var isTyping: Bool

    var body: some View {
        List {
            if settings.enabledLanguages.count > 1 {
                Section {
                    Picker("Sprache", selection: $store.language) {
                        ForEach(settings.enabledLanguages) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                HStack(spacing: 10) {
                    TextField("Neues Wort", text: $newWord)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isTyping)
                        .onSubmit(addWord)
                    Button("Hinzufügen", action: addWord)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(trimmedNewWord.isEmpty)
                }
            } footer: {
                Text("Wörter aus dieser Liste werden bei Vorschlägen und beim Wischen bevorzugt und nie autokorrigiert.")
            }

            Section {
                if store.entries.isEmpty {
                    Text("Noch keine Wörter gelernt.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.entries, id: \.word) { entry in
                        WordRow(entry: entry)
                    }
                    .onDelete { store.remove(at: $0) }
                }
            } header: {
                Text(store.entries.isEmpty ? "Wörterbuch" : "Wörterbuch – \(store.entries.count)")
            }
        }
        .navigationTitle("Gelernte Wörter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Alle löschen", role: .destructive) { isConfirmingDeleteAll = true }
                    .disabled(store.entries.isEmpty)
            }
        }
        .confirmationDialog("Alle gelernten Wörter löschen?",
                            isPresented: $isConfirmingDeleteAll,
                            titleVisibility: .visible) {
            Button("Alle löschen", role: .destructive) {
                withAnimation { store.removeAll() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das persönliche Wörterbuch wird vollständig geleert. Das lässt sich nicht rückgängig machen.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reload() }
        }
        .onChange(of: settings.enabledLanguages) { _, languages in
            // The shown language was switched off meanwhile: fall back like the keyboard does.
            if !languages.contains(store.language) { store.language = languages[0] }
        }
    }

    private var trimmedNewWord: String {
        newWord.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addWord() {
        guard store.add(word: trimmedNewWord) else { return }
        withAnimation(.snappy) { newWord = "" }
        isTyping = false
    }
}

private struct WordRow: View {
    let entry: UserLexicon.Entry

    var body: some View {
        HStack {
            Text(entry.word)
            Spacer(minLength: 12)
            Text("\(entry.count)×")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.word), \(entry.count) mal benutzt")
    }
}

#Preview {
    NavigationStack { LearnedWordsView() }
        .environmentObject(SettingsStore())
}
