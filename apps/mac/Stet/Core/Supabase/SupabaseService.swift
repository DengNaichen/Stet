import Foundation
import Observation
import Supabase
internal import Auth

@MainActor
@Observable
final class SupabaseService {
    static let shared = SupabaseService()

    enum Configuration {
        private static let placeholderURL = "https://project-name.supabase.co"
        private static let placeholderKey = "your-project-key"
        private static let defaultOAuthRedirectURLString = "naichengdeng.stet://auth-callback"
        static let oauthRedirectURL = resolvedOAuthRedirectURL(
            environment: ProcessInfo.processInfo.environment,
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            fileManager: .default
        )

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
            resolvedValue(
                for: key,
                environment: ProcessInfo.processInfo.environment,
                infoDictionary: Bundle.main.infoDictionary ?? [:],
                fileManager: .default
            )
        }

        static func resolvedOAuthRedirectURL(
            environment: [String: String],
            infoDictionary: [String: Any],
            fileManager: FileManager
        ) -> URL {
            let resolvedString = resolvedValue(
                for: "SUPABASE_OAUTH_REDIRECT_URL",
                environment: environment,
                infoDictionary: infoDictionary,
                fileManager: fileManager
            ) ?? defaultOAuthRedirectURLString

            return URL(string: resolvedString) ?? URL(string: defaultOAuthRedirectURLString)!
        }

        static func resolvedValue(
            for key: String,
            environment: [String: String],
            infoDictionary: [String: Any],
            fileManager: FileManager
        ) -> String? {
            let environmentValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let environmentValue, !environmentValue.isEmpty {
                return environmentValue
            }

            let infoValue = (infoDictionary[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let infoValue, !infoValue.isEmpty {
                return infoValue
            }

            let envFileValue = localEnvFileValues(fileManager: fileManager)[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let envFileValue, !envFileValue.isEmpty {
                return envFileValue
            }

            return nil
        }

        private static func localEnvFileValues(fileManager: FileManager) -> [String: String] {
            for url in candidateEnvFileURLs(fileManager: fileManager) {
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                    continue
                }

                let values = parseDotEnv(contents)
                if !values.isEmpty {
                    return values
                }
            }

            return [:]
        }

        private static func candidateEnvFileURLs(fileManager: FileManager) -> [URL] {
            var urls: [URL] = []
            let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            let homeDirectory = fileManager.homeDirectoryForCurrentUser

            let relativePaths = [
                ".env",
                ".env.local",
                "apps/mac/Stet/.env",
                "apps/mac/Stet/.env.local",
                "apps/backend/.env",
                "apps/backend/.env.local",
            ]

            for baseURL in [currentDirectory, homeDirectory] {
                for relativePath in relativePaths {
                    urls.append(baseURL.appendingPathComponent(relativePath))
                }
            }

            return urls
        }

        private static func parseDotEnv(_ contents: String) -> [String: String] {
            var values: [String: String] = [:]

            for rawLine in contents.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#") else {
                    continue
                }

                if let equalsIndex = line.firstIndex(of: "=") {
                    let key = line[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                    let valueStart = line.index(after: equalsIndex)
                    let value = line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !key.isEmpty else { continue }
                    values[key] = unquoteDotEnvValue(value)
                }
            }

            return values
        }

        private static func unquoteDotEnvValue(_ value: String) -> String {
            guard value.count >= 2 else { return value }

            let first = value.first
            let last = value.last
            if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                let start = value.index(after: value.startIndex)
                let end = value.index(before: value.endIndex)
                return String(value[start..<end])
            }

            return value
        }
    }

    private enum ServiceError: LocalizedError {
        case missingConfiguration

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "Supabase is not configured. Set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` in the scheme environment, target build settings, or a local .env file before signing in."
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
            supabaseKey: Configuration.projectKey,
            options: .init(
                auth: .init(
                    emitLocalSessionAsInitialSession: true
                )
            )
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

    func signIn(provider: Provider) async throws {
        try ensureConfiguration()
        _ = try await client.auth.signInWithOAuth(
            provider: provider,
            redirectTo: Configuration.oauthRedirectURL,
            scopes: provider.oauthScopes
        )
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

    func relayAuthenticationContext() async -> RelayAuthenticationContext? {
        guard isConfigured,
              let supabaseURL = URL(string: Configuration.urlString) else {
            return nil
        }

        do {
            let session = try await client.auth.session

            return RelayAuthenticationContext(
                functionsBaseURL: supabaseURL.appendingPathComponent("functions/v1"),
                publishableKey: Configuration.projectKey,
                accessToken: session.accessToken
            )
        } catch {
            AppLogger.warning(
                "Failed to resolve a refreshed Supabase session for Managed Relay: \(error.localizedDescription)"
            )
            return nil
        }
    }

    private func ensureConfiguration() throws {
        guard isConfigured else {
            throw ServiceError.missingConfiguration
        }
    }
}

extension SupabaseService: OnboardingSupabaseAuthenticating {
    var hasCurrentSession: Bool {
        currentSession != nil
    }
}
