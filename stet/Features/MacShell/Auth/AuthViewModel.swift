import Foundation
import AuthenticationServices
import Observation
internal import Auth

@MainActor
@Observable
final class AuthViewModel {
    enum AuthMode {
        case signIn
        case signUp
    }

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
        case passwordMismatch

        var errorDescription: String? {
            switch self {
            case .missingEmail:
                return "Enter the email address for your account."
            case .invalidEmail:
                return "Enter a valid email address."
            case .missingPassword:
                return "Enter your password before continuing."
            case .passwordMismatch:
                return "Passwords do not match."
            }
        }
    }

    var email = ""
    var password = ""
    var confirmPassword = ""
    var authMode: AuthMode = .signIn
    var isLoading = false
    var errorMessage: String? = nil
    var statusMessage: String? = nil
    var balanceCredits: Int? = nil

    private let supabase: SupabaseService

    init(supabase: SupabaseService) {
        self.supabase = supabase
    }

    convenience init() {
        self.init(supabase: .shared)
    }

    var canSubmit: Bool {
        !normalizedEmail.isEmpty
            && !password.isEmpty
            && (authMode == .signIn || !confirmPassword.isEmpty)
            && !isLoading
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

    var showsConfirmPasswordField: Bool {
        authMode == .signUp
    }

    var primaryActionTitle: String {
        authMode == .signIn ? "Sign In" : "Sign Up"
    }

    var modeToggleTitle: String {
        authMode == .signIn ? "Create Account" : "Sign In"
    }

    func signIn() async {
        await perform(.signIn) { email, password in
            try await supabase.signIn(email: email, password: password)
            self.password = ""
            self.confirmPassword = ""
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
            self.confirmPassword = ""
            self.statusMessage =
                "Account created. If email confirmation is enabled, check your inbox before signing in."
        }
    }

    func signOut() async {
        await perform(.signOut) { _, _ in
            try await supabase.signOut()
        }
    }

    func fetchWallet() async {
        guard let ctx = await supabase.relayAuthenticationContext() else { return }
        let url = ctx.relayBaseURL.appendingPathComponent("me/quota")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(ctx.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(ctx.publishableKey, forHTTPHeaderField: "Apikey")

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }

        struct Response: Decodable {
            struct BillingAccount: Decodable {
                let balance_credits: Int
            }
            let billing_account: BillingAccount
        }

        if let decoded = try? JSONDecoder().decode(Response.self, from: data) {
            balanceCredits = decoded.billing_account.balance_credits
        }
    }

    func clearFeedback() {
        errorMessage = nil
        statusMessage = nil
    }

    func toggleAuthMode() {
        authMode = authMode == .signIn ? .signUp : .signIn
        password = ""
        confirmPassword = ""
        clearFeedback()
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
            if action == .signUp, password != confirmPassword {
                throw ValidationError.passwordMismatch
            }
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
    }

}
