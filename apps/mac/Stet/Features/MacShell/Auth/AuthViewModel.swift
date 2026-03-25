import Foundation
import AuthenticationServices
import Observation
internal import Auth

@MainActor
@Observable
final class AuthViewModel {
    private enum AuthAction {
        case signIn
        case signUp
        case signOut

        var failurePrefix: String {
            switch self {
            case .signIn:
                return "Couldn't sign in"
            case .signUp:
                return "Couldn't create account"
            case .signOut:
                return "Couldn't sign out"
            }
        }
    }

    private enum ValidationError: LocalizedError {
        case missingEmail
        case invalidEmail
        case missingPassword

        var errorDescription: String? {
            switch self {
            case .missingEmail:
                return "Enter the email address for your account."
            case .invalidEmail:
                return "Enter a valid email address."
            case .missingPassword:
                return "Enter your password before continuing."
            }
        }
    }

    var email = ""
    var password = ""
    var isLoading = false
    var errorMessage: String? = nil
    var statusMessage: String? = nil

    private let supabase: SupabaseService

    init(supabase: SupabaseService) {
        self.supabase = supabase
    }

    convenience init() {
        self.init(supabase: .shared)
    }

    var canSubmit: Bool {
        !normalizedEmail.isEmpty && !password.isEmpty && !isLoading
    }

    var isSignedIn: Bool {
        supabase.currentSession != nil
    }

    var accountEmail: String? {
        supabase.currentSession?.user.email
    }

    var accountEmailText: String {
        accountEmail ?? "Unknown user"
    }

    var isSupabaseConfigured: Bool {
        supabase.isConfigured
    }

    var configurationStatusText: String {
        isSupabaseConfigured ? "Supabase Ready" : "Setup Required"
    }

    var configurationStatusTint: Bool {
        isSupabaseConfigured
    }

    func signIn() async {
        await perform(.signIn) { email, password in
            try await supabase.signIn(email: email, password: password)
            self.password = ""
        }
    }

    func signInWithGoogle() async {
        await performOAuth(provider: .google)
    }

    func signInWithApple() async {
        await performOAuth(provider: .apple)
    }

    func signInWithGitHub() async {
        await performOAuth(provider: .github)
    }

    func signUp() async {
        await perform(.signUp) { email, password in
            try await supabase.signUp(email: email, password: password)
            self.password = ""
            self.statusMessage =
                "Account created. If email confirmation is enabled, check your inbox before signing in."
        }
    }

    func signOut() async {
        await perform(.signOut) { _, _ in
            try await supabase.signOut()
        }
    }

    func clearFeedback() {
        errorMessage = nil
        statusMessage = nil
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func perform(
        _ action: AuthAction,
        operation: (_ email: String, _ password: String) async throws -> Void
    ) async {
        errorMessage = nil
        statusMessage = nil

        do {
            let credentials = try validatedCredentials(for: action)
            email = credentials.email
            isLoading = true
            defer { isLoading = false }
            try await operation(credentials.email, credentials.password)
        } catch {
            errorMessage = message(for: error, action: action)
        }
    }

    private func performOAuth(provider: Provider) async {
        errorMessage = nil
        statusMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            statusMessage = "Opening \(provider.displayName) sign-in..."
            try await supabase.signIn(provider: provider)
        } catch {
            guard !isCancellationError(error) else {
                statusMessage = nil
                return
            }

            errorMessage = message(for: error, provider: provider)
        }
    }

    private func validatedCredentials(
        for action: AuthAction
    ) throws -> (email: String, password: String) {
        switch action {
        case .signOut:
            return ("", "")
        case .signIn, .signUp:
            let email = normalizedEmail
            guard !email.isEmpty else { throw ValidationError.missingEmail }
            guard email.contains("@"), email.contains(".") else { throw ValidationError.invalidEmail }
            guard !password.isEmpty else { throw ValidationError.missingPassword }
            return (email, password)
        }
    }

    private func message(for error: Error, action: AuthAction) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }

        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            return action.failurePrefix
        }

        return "\(action.failurePrefix): \(description)"
    }

    private func message(for error: Error, provider: Provider) -> String {
        let prefix = "Couldn't sign in with \(provider.displayName)"

        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }

        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            return prefix
        }

        return "\(prefix): \(description)"
    }

    private func isCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == ASWebAuthenticationSessionErrorDomain
            && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
            || nsError.domain == ASAuthorizationError.errorDomain
            && nsError.code == ASAuthorizationError.canceled.rawValue
    }

}
