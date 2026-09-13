import SwiftUI

/// „Ausprobieren“ – a scratch pad to test the keyboard plus the three core gestures.
struct PlaygroundView: View {

    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var engineLoader = DemoEngineLoader.shared
    @State private var text = ""
    @State private var isEditing = false
    @State private var useUmlautKeyboard = true

    private static let tips: [Tip] = [
        Tip(symbol: "hand.draw",
            title: "Wischen",
            detail: "Zieh den Finger ohne abzusetzen über die Buchstaben – Umlaut erkennt das ganze Wort."),
        Tip(symbol: "hand.tap",
            title: "Lange drücken",
            detail: "Halte eine Taste gedrückt für ä-Varianten, ß oder die Zahlen in der obersten Reihe."),
        Tip(symbol: "arrow.left.and.right",
            title: "Cursor bewegen",
            detail: "Halte die Leertaste gedrückt und zieh sie – der Cursor folgt deinem Finger."),
        Tip(symbol: "sparkles",
            title: "KI fragen",
            detail: "Tippe auf ✦ neben der Ausblenden-Taste: korrigieren, umformulieren, weiterschreiben, übersetzen. Schlüssel und Modell wählst du unter Einstellungen › KI."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                editor
                keyboardSwitch
                VStack(spacing: 12) {
                    ForEach(Self.tips) { tip in
                        TipCard(tip: tip, accent: settings.accent.color)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { endEditing() }   // tapping outside the editor closes the keyboard
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Ausprobieren")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Löschen") { withAnimation(.snappy) { text = "" } }
                    .disabled(text.isEmpty)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                DemoTextView(text: $text,
                             useUmlautKeyboard: useUmlautKeyboard,
                             engine: engineLoader.engine,
                             settingsVersion: settingsVersion,
                             onFocusChange: { isEditing = $0 })
                    .frame(height: 200)
                    .padding(4)
                if text.isEmpty {
                    Text("Tippe oder wische hier…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isEditing ? settings.accent.color.opacity(0.6) : Color.secondary.opacity(0.18),
                                  lineWidth: isEditing ? 2 : 1)
            )
            .animation(.easeInOut(duration: 0.2), value: isEditing)

            HStack {
                Text(wordCount == 1 ? "1 Wort" : "\(wordCount) Wörter")
                Spacer()
                Text("\(text.count) Zeichen")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 4)
        }
    }

    /// Lets people compare with the system keyboard; the in-app demo needs no setup at all.
    private var keyboardSwitch: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.title3)
                .foregroundStyle(settings.accent.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Umlaut hier direkt testen")
                    .font(.subheadline.weight(.semibold))
                Text(settings.keyboardEnabled
                     ? "Auch ohne Umschalten über die Globus-Taste."
                     : "Funktioniert schon vor der Aktivierung in den Einstellungen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $useUmlautKeyboard).labelsHidden()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Changes whenever a setting that affects the keyboard's look changes.
    private var settingsVersion: Int {
        var h = Hasher()
        h.combine(settings.theme); h.combine(settings.accent); h.combine(settings.keySize)
        h.combine(settings.swipeTrail); h.combine(settings.keyPreview); h.combine(settings.longPressNumbers)
        h.combine(settings.commaKey); h.combine(settings.emojiOnCommaKey)
        h.combine(settings.enabledLanguages); h.combine(settings.currentLanguage)
        return h.finalize()
    }

    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

private struct Tip: Identifiable {
    let symbol: String
    let title: String
    let detail: String
    var id: String { title }
}

private struct TipCard: View {
    let tip: Tip
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: tip.symbol)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title)
                    .font(.subheadline.weight(.semibold))
                Text(tip.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    NavigationStack { PlaygroundView() }
        .environmentObject(SettingsStore())
}
