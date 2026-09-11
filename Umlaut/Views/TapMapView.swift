import SwiftUI
import KeyboardCore

/// „Deine Tap Map“ – shows how the keyboard has quietly moved each letter key's hit target to
/// where this user actually taps it, with a way to start over.
struct TapMapView: View {

    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var store = TapMapStore()
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedID: String?
    @State private var isConfirmingReset = false

    private var selected: TapMapStore.LayerInfo? {
        store.layers.first { $0.id == selectedID } ?? store.primary
    }

    var body: some View {
        List {
            Section {
                TapMapCanvas(layer: selected?.layer, arrangement: selected?.arrangement, accent: settings.accent)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                    .animation(.snappy(duration: 0.35), value: selected)

                if store.layers.count > 1 {
                    Picker("Tastatur", selection: Binding(get: { selected?.id }, set: { selectedID = $0 })) {
                        ForEach(store.layers) { info in
                            Text(store.title(for: info)).tag(Optional(info.id))
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }
            } footer: {
                if selected == nil {
                    Text("Noch keine Daten. Tippe einfach ein paar Sätze – die Karte passt sich im Hintergrund an.")
                } else {
                    Text("So hat Umlaut deine Tasten im Hintergrund angepasst. Blass umrandet ist die sichtbare Taste, gefüllt die gelernte Trefferfläche – zur Verdeutlichung \(Int(TapMapCanvas.exaggeration))-fach verstärkt.")
                }
            }

            if let info = selected {
                Section("Statistik") {
                    LabeledContent("Ausgewertete Tipps", value: info.layer.sampleCount.formatted())
                    LabeledContent("Angepasste Tasten", value: "\(info.layer.learnedKeyCount) von \(KeyAlphabet.count)")
                }
            }

            Section {
                Toggle("Tippverhalten lernen", isOn: $settings.adaptiveTapMap)
            } footer: {
                Text("Ausgeschaltet tippt die Tastatur wieder auf die sichtbaren Tasten; die gelernte Karte bleibt erhalten.")
            }
        }
        .navigationTitle("Deine Tap Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Zurücksetzen", role: .destructive) { isConfirmingReset = true }
                    .disabled(store.layers.isEmpty)
            }
        }
        .confirmationDialog("Tap Map zurücksetzen?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) {
                withAnimation { store.reset() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alles Gelernte über dein Tippverhalten wird verworfen. Die Tastatur fängt von vorn an.")
        }
        .onAppear(perform: store.reload)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reload() }
        }
    }
}

/// The letter rows, each cap drawn where the map has learned this user taps it. The visible key
/// stays as a faint outline so the drift is readable; empty keys sit exactly on their outline.
struct TapMapCanvas: View {
    var layer: TapMap.Layer?
    /// The layer's letters in reading order (see `TapMap.arrangement(of:)`); relabels the caps so
    /// a QWERTY layer shows y and z where that layout has them. nil = German layout.
    var arrangement: String?
    var accent: KeyboardSettings.Accent = .blue

    @Environment(\.colorScheme) private var scheme

    /// Shifts are a few points at most; multiplied for the picture, as SwiftKey does.
    static let exaggeration: CGFloat = 3

    private static let referenceWidth: CGFloat = 390
    private static let referenceHeight: CGFloat = 168

    /// The three letter rows of the German layout, laid out with the real geometry code.
    private static let layout: KeyboardLayout = {
        let letters = GermanLayouts.letters()
        return KeyboardLayout(layer: .letters, rows: Array(letters.rows.prefix(3)), columns: letters.columns)
    }()

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / Self.referenceWidth, 0.01)
            let metrics = KeyboardGeometry.Metrics(horizontalGap: 6 * scale, verticalGap: 11 * scale,
                                                   sideInset: 10 * scale, topInset: 12 * scale, bottomInset: 12 * scale)
            let geometry = KeyboardGeometry(layout: Self.layout, size: proxy.size, metrics: metrics)
            let pitchX = geometry.unitWidth + geometry.horizontalGap, pitchY = geometry.rowHeight + geometry.verticalGap
            let offsets = layer?.offsets
            let radius = max(3, 8 * scale)
            let letters = arrangement.map(Array.init)
            ZStack {
                ForEach(Array(geometry.keyFrames.enumerated()), id: \.element) { index, kf in
                    let label = letters.flatMap { $0.count == geometry.keyFrames.count ? String($0[index]) : nil } ?? kf.key.label
                    let code = label.first.flatMap(KeyAlphabet.code(for:))
                    let shift = drift(code: code, offsets: offsets, pitchX: pitchX, pitchY: pitchY)
                    let confidence = confidence(code: code)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(outline, lineWidth: max(1, scale))
                        .frame(width: kf.frame.width, height: kf.frame.height)
                        .position(x: kf.frame.midX, y: kf.frame.midY)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(accent.color.opacity(0.45 + 0.55 * confidence))
                        .overlay {
                            Text(label)
                                .font(.system(size: geometry.rowHeight * 0.5, weight: .regular, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(width: kf.frame.width, height: kf.frame.height)
                        .position(x: kf.frame.midX + shift.x, y: kf.frame.midY + shift.y)
                        .accessibilityLabel(accessibilityLabel(for: label, shift: shift, pitchX: pitchX, pitchY: pitchY))
                }
            }
        }
        .aspectRatio(Self.referenceWidth / Self.referenceHeight, contentMode: .fit)
        .background(scheme == .dark ? Color(.secondarySystemGroupedBackground) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tap Map der Buchstabentasten")
    }

    private var outline: Color {
        scheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
    }

    /// Learned shift relative to the neutral map, in points, exaggerated for the picture.
    private func drift(code: UInt8?, offsets: TapMap.Offsets?, pitchX: CGFloat, pitchY: CGFloat) -> CGPoint {
        guard let code, let offsets else { return .zero }
        let learned = offsets.shift(code: code, pitchX: pitchX, pitchY: pitchY)
        let neutral = TapMap.Offsets.neutral.shift(code: code, pitchX: pitchX, pitchY: pitchY)
        return CGPoint(x: (learned.x - neutral.x) * Self.exaggeration, y: (learned.y - neutral.y) * Self.exaggeration)
    }

    /// 0 for a key without taps, 1 once the learned offset outweighs the built-in default.
    private func confidence(code: UInt8?) -> CGFloat {
        guard let code, let layer, Int(code) < layer.stats.count else { return 0 }
        return CGFloat(min(1, layer.stats[Int(code)].count / TapMap.Tuning.pseudoCount))
    }

    private func accessibilityLabel(for label: String, shift: CGPoint, pitchX: CGFloat, pitchY: CGFloat) -> String {
        let dx = shift.x / Self.exaggeration / pitchX * 100, dy = shift.y / Self.exaggeration / pitchY * 100
        guard abs(dx) >= 1 || abs(dy) >= 1 else { return "\(label): mittig" }
        var parts: [String] = []
        if abs(dx) >= 1 { parts.append("\(Int(abs(dx).rounded())) Prozent nach \(dx > 0 ? "rechts" : "links")") }
        if abs(dy) >= 1 { parts.append("\(Int(abs(dy).rounded())) Prozent nach \(dy > 0 ? "unten" : "oben")") }
        return "\(label): " + parts.joined(separator: ", ")
    }
}

#Preview("Gelernt") {
    var layer = TapMap.Layer()
    for (i, c) in KeyAlphabet.letters.enumerated() {
        let right = "poiuzt".contains(c) ? -0.12 : 0.1
        layer.stats[i] = TapMap.KeyStat(dx: Float(right) * Float(i % 3 + 1) / 2, dy: Float(i % 4) * 0.05 - 0.05, count: Float(i * 3))
    }
    layer.sampleCount = 812
    return NavigationStack {
        List {
            TapMapCanvas(layer: layer, accent: .blue)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
        }
    }
    .environmentObject(SettingsStore())
}

#Preview("Leer") {
    NavigationStack { TapMapView() }
        .environmentObject(SettingsStore())
}
