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
            return "Use Managed Relay for dictation when signed in. Otherwise fall back to the local provider API key."
        case .managed:
            return "Use the authenticated relay for dictation. Current relay coverage is limited to the dictation pipeline and requires a signed-in Supabase session."
        case .byok:
            return "Always use the local provider API key and bypass the relay."
        }
    }

    nonisolated var requiresAuthenticatedSession: Bool {
        self == .managed
    }

    nonisolated var requiresLocalAPIKey: Bool {
        self == .byok
    }
}
