import Foundation
import Security

/// The user's provider keys, in the keychain and shared with the keyboard extension through the
/// app group (an app group is a keychain access group on iOS). The extension reads keys only
/// with "Allow Full Access", the same permission it needs for the network anyway.
public final class AIKeyStore: @unchecked Sendable {

    public static let shared = AIKeyStore(service: "de.codext.umlaut.ai", accessGroup: KeyboardSettings.appGroup)

    private let service: String
    private let accessGroup: String?
    private let inMemory: Bool
    private let lock = NSLock()
    private var cache: [AIProvider: String?] = [:]
    /// Where keys go when the keychain refuses the access group (missing entitlement, e.g. some
    /// simulator setups), so the feature still works there instead of failing silently.
    private let fallback: UserDefaults?

    public init(service: String, accessGroup: String?) {
        self.service = service
        self.accessGroup = accessGroup
        self.inMemory = false
        self.fallback = accessGroup.flatMap { UserDefaults(suiteName: $0) }
    }

    /// Keys live only in this process – for tests and previews.
    public init(inMemory: Bool) {
        service = "memory"
        accessGroup = nil
        self.inMemory = inMemory
        fallback = nil
    }

    public func key(for provider: AIProvider) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[provider] { return cached }
        let value = inMemory ? nil : read(provider)
        cache[provider] = .some(value)
        return value
    }

    public func hasKey(for provider: AIProvider) -> Bool {
        guard let k = key(for: provider) else { return false }
        return !k.isEmpty
    }

    /// Providers with a key, in picker order.
    public var configuredProviders: [AIProvider] { AIProvider.allCases.filter(hasKey) }

    /// Stores or, with nil / an empty string, removes the key.
    public func setKey(_ key: String?, for provider: AIProvider) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        lock.lock(); defer { lock.unlock() }
        cache[provider] = .some(value)
        guard !inMemory else { return }
        write(value, for: provider)
    }

    /// Forgets cached values so the next read sees what the other process stored.
    public func invalidateCache() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
    }

    // MARK: Keychain

    private static let fallbackPrefix = "ai.key."

    private func query(_ provider: AIProvider) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
#if os(iOS)
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
#endif
        return q
    }

    private func read(_ provider: AIProvider) -> String? {
        var q = query(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let s = String(data: data, encoding: .utf8) { return s }
        return fallback?.string(forKey: Self.fallbackPrefix + provider.rawValue)
    }

    /// Writes to the shared keychain group; a process without access to it (missing
    /// entitlement) keeps the key in the shared defaults instead, so both processes still agree.
    private func write(_ value: String?, for provider: AIProvider) {
        fallback?.removeObject(forKey: Self.fallbackPrefix + provider.rawValue)
        let q = query(provider)
        let deleteStatus = SecItemDelete(q as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else {
            if deleteStatus == errSecMissingEntitlement { fallback?.removeObject(forKey: Self.fallbackPrefix + provider.rawValue) }
            return
        }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status != errSecSuccess else { return }
        fallback?.set(value, forKey: Self.fallbackPrefix + provider.rawValue)
    }
}
