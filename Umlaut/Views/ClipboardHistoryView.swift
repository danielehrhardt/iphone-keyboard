import SwiftUI
import KeyboardCore

/// „Zwischenablage“ – the copied texts and images the keyboard offers, with a way to remove them.
struct ClipboardHistoryView: View {

    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var store = ClipboardStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isConfirmingDeleteAll = false
    @State private var copiedID: UUID?

    var body: some View {
        List {
            if !settings.clipboardHistory {
                Section {
                    Label("Der Verlauf ist ausgeschaltet – die Tastatur merkt sich nichts Neues.", systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                if store.items.isEmpty {
                    Text("Noch nichts kopiert.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.items) { item in
                        ItemRow(item: item, thumbnail: store.thumbnail(for: item), isCopied: copiedID == item.id)
                            .contentShape(Rectangle())
                            .onTapGesture { copy(item) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { withAnimation { store.remove(item) } } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { store.remove(at: $0) }
                }
            } header: {
                Text(store.items.isEmpty ? "Verlauf" : "Verlauf – \(store.items.count)")
            } footer: {
                Text("Tippen kopiert einen Eintrag zurück in die Zwischenablage. Aufbewahrt für: \(settings.clipboardRetention.title).")
            }
        }
        .navigationTitle("Zwischenablage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Alle löschen", role: .destructive) { isConfirmingDeleteAll = true }
                    .disabled(store.items.isEmpty)
            }
        }
        .confirmationDialog("Gesamten Verlauf löschen?",
                            isPresented: $isConfirmingDeleteAll,
                            titleVisibility: .visible) {
            Button("Alle löschen", role: .destructive) {
                withAnimation { store.removeAll() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle gemerkten Texte und Bilder werden entfernt. Das lässt sich nicht rückgängig machen.")
        }
        .onAppear { store.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reload() }
        }
        .onChange(of: settings.clipboardRetention) { _, _ in store.reload() }
    }

    private func copy(_ item: ClipboardItem) {
        store.copy(item)
        withAnimation(.snappy) { copiedID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { if copiedID == item.id { copiedID = nil } }
        }
    }
}

private struct ItemRow: View {
    let item: ClipboardItem
    let thumbnail: UIImage?
    let isCopied: Bool

    var body: some View {
        HStack(spacing: 12) {
            preview
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.preview)
                    .lineLimit(2)
                Text(item.createdAt, format: .relative(presentation: .named))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isCopied {
                Label("Kopiert", systemImage: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
                    .labelStyle(.titleAndIcon)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((item.kind == .image ? "Bild, " : "") + item.preview)
        .accessibilityHint("Zum Kopieren tippen")
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.secondary.opacity(0.12)
                Image(systemName: item.kind == .image ? "photo" : "text.alignleft")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack { ClipboardHistoryView() }
        .environmentObject(SettingsStore())
}
