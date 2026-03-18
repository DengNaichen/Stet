import Foundation

enum AIExecutionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case managed
    case byok

    nonisolated var id: Self { self }

    nonisolated var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .managed:
            return "Managed Relay"
        case .byok:
            return "BYOK"
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .automatic:
            return "Managed Relay"
        case .managed:
            return "authenticated relay"
        case .byok:
            return "local provider API key"
        }
    }

    nonisolated var requiresAuthenticatedSession: Bool {
        self == .managed
    }

    nonisolated var requiresLocalAPIKey: Bool {
        self == .byok
    }
}
