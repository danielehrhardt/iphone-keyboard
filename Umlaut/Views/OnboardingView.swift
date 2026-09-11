import SwiftUI
import KeyboardCore

/// „Start / Einrichtung“ – hero, the three activation steps and the privacy promise.
struct OnboardingView: View {

    @EnvironmentObject private var settings: SettingsStore
    @State private var didOpenSettings = false
    @State private var celebrate = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                if settings.keyboardEnabled { successCard }
                stepsCard
                privacyCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(background)
        .navigationTitle("Umlaut")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings.keyboardEnabled) { _, enabled in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { celebrate = enabled }
        }
        .onAppear { celebrate = settings.keyboardEnabled }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 14) {
            Text("Umlaut")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(settings.accent.color)
            Text("Die deutsche Tastatur mit Swipe")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            KeyboardPreview(accent: settings.accent,
                            keySize: settings.keySize,
                            trail: .hallo,
                            animatesTrail: true)
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                .padding(.top, 4)
        }
        .padding(.top, 12)
    }

    // MARK: Erfolg

    private var successCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34))
                .foregroundStyle(settings.accent.color)
                .symbolEffect(.bounce, value: celebrate)
                .scaleEffect(celebrate ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 3) {
                Text("Umlaut ist aktiv")
                    .font(.headline)
                Text("Wechsle mit 🌐 auf Umlaut und leg los.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(settings.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(settings.accent.color.opacity(0.35), lineWidth: 1)
        )
        .transition(.scale(scale: 0.94).combined(with: .opacity))
    }

    // MARK: Schritte

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("So aktivierst du Umlaut")
                .font(.headline)
                .padding(.bottom, 14)

            StepRow(number: 1,
                    title: "Einstellungen öffnen",
                    detail: "Öffne die iPhone-Einstellungen bei Umlaut.",
                    isDone: didOpenSettings || settings.keyboardEnabled,
                    accent: settings.accent.color,
                    actionTitle: "Einstellungen öffnen") {
                didOpenSettings = true
                settings.openSystemSettings()
            }

            divider

            StepRow(number: 2,
                    title: "Tastaturen → Umlaut aktivieren",
                    detail: "Tippe auf „Tastaturen“ und schalte Umlaut ein.",
                    isDone: settings.keyboardEnabled,
                    accent: settings.accent.color)

            divider

            StepRow(number: 3,
                    title: "Vollen Zugriff erlauben",
                    detail: "Nötig für Haptik und damit Einstellungen zwischen App und Tastatur synchron bleiben. Es werden keine Tastenanschläge übertragen.",
                    isDone: settings.fullAccessConfirmed,
                    accent: settings.accent.color,
                    actionTitle: settings.fullAccessConfirmed ? nil : "Erledigt") {
                withAnimation(.snappy) { settings.fullAccessConfirmed = true }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var divider: some View {
        Divider().padding(.leading, 44).padding(.vertical, 14)
    }

    // MARK: Datenschutz

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title3)
                .foregroundStyle(settings.accent.color)
            VStack(alignment: .leading, spacing: 4) {
                Text("Alles bleibt auf deinem iPhone")
                    .font(.subheadline.weight(.semibold))
                Text("Umlaut hat keine Server, keine Analyse und kein Netzwerk. Wörterbuch und Einstellungen liegen ausschließlich lokal auf dem Gerät.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var background: some View {
        LinearGradient(colors: [settings.accent.color.opacity(0.22), .clear],
                       startPoint: .top, endPoint: .center)
            .background(Color(.systemGroupedBackground))
            .ignoresSafeArea()
    }
}

/// One numbered activation step with an optional call to action.
private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String
    let isDone: Bool
    let accent: Color
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            badge
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(isDone ? "Erledigt" : "Offen")
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(isDone ? accent : Color.secondary.opacity(0.18))
                .frame(width: 30, height: 30)
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(number)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: isDone)
    }
}

#Preview {
    NavigationStack { OnboardingView() }
        .environmentObject(SettingsStore())
}
