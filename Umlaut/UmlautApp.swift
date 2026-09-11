import SwiftUI
import KeyboardCore
import KeyboardCore

@main
struct UmlautApp: App {
    init() {
        // UI tests pass this to start from a clean personal dictionary.
        if CommandLine.arguments.contains("--reset-user-lexicon") {
            for language in KeyboardLanguage.allCases {
                let lexicon = UserLexicon.shared(appGroup: KeyboardSettings.appGroup, language: language)
                lexicon.removeAll()
                lexicon.saveNow()
            }
        }
    }


    @StateObject private var settings = SettingsStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .tint(settings.accent.color)
                .onChange(of: scenePhase) { _, phase in
                    // The keyboard may have been enabled – or may have changed settings – while we were away.
                    if phase == .active { settings.reload() }
                }
        }
    }
}

struct RootView: View {

    enum Tab: Hashable {
        case start, playground, settings
    }

    @EnvironmentObject private var settings: SettingsStore
    @State private var selection: Tab = .start

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { OnboardingView() }
                .tabItem { Label("Start", systemImage: "sparkles") }
                .tag(Tab.start)

            NavigationStack { PlaygroundView() }
                .tabItem { Label("Ausprobieren", systemImage: "keyboard") }
                .tag(Tab.playground)

            NavigationStack { SettingsView() }
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .onAppear {
            if settings.keyboardEnabled && !settings.onboardingDone {
                settings.onboardingDone = true
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(SettingsStore())
}
