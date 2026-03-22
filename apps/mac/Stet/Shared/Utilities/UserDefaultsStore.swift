import Foundation

nonisolated final class UserDefaultsStore: @unchecked Sendable {
    private let defaults: UserDefaults

    nonisolated init(_ defaults: UserDefaults) {
        self.defaults = defaults
    }

    nonisolated func object(forKey key: String) -> Any? {
        defaults.object(forKey: key)
    }

    nonisolated func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    nonisolated func stringArray(forKey key: String) -> [String]? {
        defaults.stringArray(forKey: key)
    }

    nonisolated func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    nonisolated func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
