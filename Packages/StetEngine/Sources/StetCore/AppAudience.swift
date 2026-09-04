import Foundation

public enum AppAudience: String, Codable, Sendable {
    case human
    case ai

    public nonisolated var isAI: Bool {
        self == .ai
    }
}
