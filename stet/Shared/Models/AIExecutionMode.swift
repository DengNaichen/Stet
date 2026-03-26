import Foundation

enum AIExecutionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case managed
    case byok

    nonisolated var id: Self { self }

    nonisolated var title: String {
        switch self {
        case .managed:
            return "Stet account"
        case .byok:
            return "Your own key"
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .managed:
            return "Use your signed-in Stet account"
        case .byok:
            return "Use your own provider key"
        }
    }

    nonisolated var requiresAuthenticatedSession: Bool {
        self == .managed
    }

    nonisolated var requiresLocalAPIKey: Bool {
        self == .byok
    }
}
