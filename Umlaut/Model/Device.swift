import Foundation

enum Device {
    /// iPhone Duo, Apple's foldable (inner display 669 x 951 pt).
    static let isFoldable: Bool = foldableModels.contains(modelIdentifier)

    private static let foldableModels: Set<String> = ["iPhone19,4"]

    private static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
