import SwiftUI
import KeyboardCore

/// A non-interactive rendering of the German QWERTZ layer, laid out with the very same
/// `KeyboardGeometry` the extension uses, so the preview matches the real keyboard exactly.
struct KeyboardPreview: View {

    enum Trail {
        case none
        /// Decorative gesture across h → a → l → o.
        case hallo
    }

    var accent: KeyboardSettings.Accent = .blue
    var keySize: KeyboardSettings.KeySize = .regular
    /// `nil` follows the surrounding environment.
    var scheme: ColorScheme?
    var trail: Trail = .none
    var animatesTrail = false
    var cornerRadius: CGFloat = 16

    @Environment(\.colorScheme) private var environmentScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimatingTrail = false

    /// Length of the bright head that runs along the trail, as a fraction of the whole path.
    private static let tailLength: CGFloat = 0.45

    /// Reference width of an iPhone keyboard; all metrics are scaled from it.
    private static let referenceWidth: CGFloat = 390
    private static let referenceHeight: CGFloat = 216
    private static let layout = GermanLayouts.letters()

    private var isDark: Bool { (scheme ?? environmentScheme) == .dark }
    private var accentColor: Color { accent.color }

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / Self.referenceWidth, 0.01)
            let geometry = KeyboardGeometry(layout: Self.layout, size: proxy.size, metrics: metrics(scale: scale))
            ZStack {
                ForEach(geometry.keyFrames, id: \.self) { keyFrame in
                    cap(for: keyFrame, geometry: geometry, scale: scale)
                        .frame(width: keyFrame.frame.width, height: keyFrame.frame.height)
                        .position(x: keyFrame.frame.midX, y: keyFrame.frame.midY)
                }
                if trail == .hallo {
                    swipeTrail(in: geometry, scale: scale)
                }
            }
        }
        .aspectRatio(Self.referenceWidth / (Self.referenceHeight * keySize.heightMultiplier), contentMode: .fit)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Vorschau der deutschen Tastatur")
        .onAppear(perform: startTrailAnimation)
    }

    // MARK: Keys

    private func metrics(scale: CGFloat) -> KeyboardGeometry.Metrics {
        KeyboardGeometry.Metrics(horizontalGap: 6 * scale, verticalGap: 11 * scale,
                                 sideInset: 3 * scale, topInset: 8 * scale, bottomInset: 4 * scale)
    }

    @ViewBuilder
    private func cap(for keyFrame: KeyFrame, geometry: KeyboardGeometry, scale: CGFloat) -> some View {
        let key = keyFrame.key
        let isReturn = key.action == .newline
        ZStack {
            RoundedRectangle(cornerRadius: max(2, 5 * scale), style: .continuous)
                .fill(capColor(for: key, isReturn: isReturn))
                .shadow(color: .black.opacity(isDark ? 0.4 : 0.25), radius: 0, x: 0, y: max(0.5, scale))
            label(for: key, rowHeight: geometry.rowHeight)
                .foregroundStyle(isReturn ? Color.white : (isDark ? Color.white : Color.black))
        }
    }

    @ViewBuilder
    private func label(for key: Key, rowHeight: CGFloat) -> some View {
        if let symbol = key.symbolName {
            Image(systemName: symbol)
                .font(.system(size: rowHeight * 0.34, weight: .regular))
        } else if key.action == .space {
            EmptyView()
        } else {
            Text(key.isLetter ? key.label.uppercased() : key.label)
                .font(.system(size: rowHeight * (key.isLetter ? 0.46 : 0.36), weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
    }

    private func capColor(for key: Key, isReturn: Bool) -> Color {
        if isReturn { return accentColor }
        if key.isFunction { return isDark ? Color(white: 0.27) : Color(red: 0.68, green: 0.70, blue: 0.73) }
        return isDark ? Color(white: 0.42) : .white
    }

    private var backgroundColor: Color {
        isDark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(red: 0.82, green: 0.83, blue: 0.85)
    }

    // MARK: Swipe trail

    private var trailGradient: LinearGradient {
        LinearGradient(colors: [accentColor.opacity(0.15), accentColor, accentColor.opacity(0.85)],
                       startPoint: .leading, endPoint: .trailing)
    }

    /// The full gesture, plus a brighter head sweeping along it.
    @ViewBuilder
    private func swipeTrail(in geometry: KeyboardGeometry, scale: CGFloat) -> some View {
        let centers = geometry.letterCenters
        let points = "halo".compactMap { centers[$0] }
        let style = StrokeStyle(lineWidth: max(2, geometry.rowHeight * 0.24), lineCap: .round, lineJoin: .round)
        let sweeps = animatesTrail && !reduceMotion
        ZStack {
            TrailShape(points: points, phase: 1, tail: 0)
                .stroke(accentColor.opacity(0.3), style: style)
            TrailShape(points: points,
                       phase: sweeps ? (isAnimatingTrail ? 1 + Self.tailLength : 0) : 1,
                       tail: sweeps ? Self.tailLength : 0)
                .stroke(trailGradient, style: style)
        }
        .blur(radius: max(0.5, scale * 1.2))
        .allowsHitTesting(false)
    }

    private func startTrailAnimation() {
        guard trail == .hallo, animatesTrail, !reduceMotion, !isAnimatingTrail else { return }
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: false)) {
            isAnimatingTrail = true
        }
    }
}

/// A rounded polyline through the given points (quadratic smoothing at every corner).
/// `tail == 0` draws the whole path; otherwise only the segment ending at `phase`,
/// which is what gets animated (the raw phase interpolates, unlike clamped trim bounds).
private struct TrailShape: Shape {
    var points: [CGPoint]
    var phase: CGFloat
    var tail: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let full = smoothPath()
        guard tail > 0 else { return full }
        let to = min(max(phase, 0), 1)
        let from = min(max(phase - tail, 0), 1)
        guard to > from else { return Path() }
        return full.trimmedPath(from: from, to: to)
    }

    private func smoothPath() -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            if points.count == 2 { path.addLine(to: points[1]) }
            return path
        }
        for index in 1..<(points.count - 1) {
            let current = points[index], next = points[index + 1]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: current)
        }
        path.addQuadCurve(to: points[points.count - 1], control: points[points.count - 2])
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        KeyboardPreview(accent: .indigo, trail: .hallo)
        KeyboardPreview(accent: .orange, keySize: .compact, scheme: .dark)
    }
    .padding()
}
