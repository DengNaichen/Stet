import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class SupabaseService {
    static let shared = SupabaseService()

    private enum Configuration {
        private static let environment = ProcessInfo.processInfo.environment
        private static let infoDictionary = Bundle.main.infoDictionary ?? [:]
        private static let placeholderURL = "https://project-name.supabase.co"
        private static let placeholderKey = "your-project-key"

        static let urlString =
            resolvedValue(for: "SUPABASE_URL")
            ?? placeholderURL

        static let projectKey =
            resolvedValue(for: "SUPABASE_PUBLISHABLE_KEY")
            ?? placeholderKey

        static var isConfigured: Bool {
            urlString != placeholderURL &&
                projectKey != placeholderKey &&
                !projectKey.isEmpty
        }

        private static func resolvedValue(for key: String) -> String? {
            let environmentValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let environmentValue, !environmentValue.isEmpty {
                return environmentValue
            }

            let infoValue = (infoDictionary[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let infoValue, !infoValue.isEmpty {
                return infoValue
            }

            return nil
        }
    }

    private enum ServiceError: LocalizedError {
        case missingConfiguration

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "Supabase is not configured. Set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` in the scheme environment or target build settings before signing in."
            }
        }
    }

    let client: SupabaseClient
    private var authStateTask: Task<Void, Never>?

    private(set) var currentSession: Session?
    var isConfigured: Bool { Configuration.isConfigured }

    private init() {
        guard let supabaseURL = URL(string: Configuration.urlString) else {
            preconditionFailure("Invalid SUPABASE_URL: \(Configuration.urlString)")
        }

        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: Configuration.projectKey
        )
        currentSession = client.auth.currentSession
        authStateTask = Task { @MainActor [weak self, client] in
            for await (event, session) in client.auth.authStateChanges {
                AppLogger.info("Supabase auth event: \(String(describing: event))")
                self?.currentSession = session
            }
        }
    }

    // MARK: - Email Login
    func signIn(email: String, password: String) async throws {
        try ensureConfiguration()
        try await client.auth.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        try ensureConfiguration()
        try await client.auth.signUp(email: email, password: password)
    }

    func signOut() async throws {
        try ensureConfiguration()
        try await client.auth.signOut()
    }

    var functions: FunctionsClient {
        client.functions
    }

    var relayAuthenticationContext: RelayAuthenticationContext? {
        guard isConfigured,
              let currentSession,
              let supabaseURL = URL(string: Configuration.urlString) else {
            return nil
        }

        return RelayAuthenticationContext(
            functionsBaseURL: supabaseURL.appendingPathComponent("functions/v1"),
            publishableKey: Configuration.projectKey,
            accessToken: currentSession.accessToken
        )
    }

    private func ensureConfiguration() throws {
        guard isConfigured else {
            throw ServiceError.missingConfiguration
        }
    }
}
