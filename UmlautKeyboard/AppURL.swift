import Foundation

/// URLs the keyboard uses to hand the user over to the app (`umlaut://…`, see the app's Info.plist).
enum AppURL {
    static let scheme = "umlaut"
    /// Opens the app on its settings tab.
    static let settings = URL(string: "\(scheme)://settings")!

    /// True if `url` asks for the settings tab.
    static func isSettings(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == "settings"
    }
}
