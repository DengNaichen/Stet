#if os(macOS)
    import AuthenticationServices
    import Combine
    import Foundation
    import KeyboardShortcuts
    internal import Auth

    @MainActor
    final class OnboardingViewModel: ObservableObject {
        enum AuthMode {
            case signIn
            case signUp
        }

        enum LocalWhisperDownloadState: Equatable {
            case idle
            case running(LocalWhisperDownloadStage)
            case ready(modelPath: String)
            case failed(String)
        }

        private enum LoginValidationError: LocalizedError {
            case missingEmail
            case invalidEmail
            case missingPassword
            case passwordMismatch

            var errorDescription: String? {
                switch self {
                case .missingEmail:
                    return "Please enter email"
                case .invalidEmail:
                    return "Please enter valid email "
                case .missingPassword:
                    return "Please enter password"
                case .passwordMismatch:
                    return "Passwords do not match"
                }
            }
        }

        @Published var apiKeyProvider: DictationProvider {
            didSet {
                if apiKeyProvider != lastValidatedProvider {
                    resetAPIKeyValidationState()
                }
            }
        }
        @Published var apiKey = "" {
            didSet {
                if apiKey != lastValidatedKey {
                    resetAPIKeyValidationState()
                }
            }
        }
        @Published private(set) var isValidatingAPIKey = false
        @Published private(set) var isAPIKeyValidated = false
        @Published private(set) var apiKeyStatusMessage: String?
        @Published private(set) var apiKeyErrorMessage: String?
        @Published var email = ""
        @Published var password = ""
        @Published var confirmPassword = ""
        @Published private(set) var authMode: AuthMode = .signIn
        @Published private(set) var isAuthenticating = false
        @Published private(set) var authErrorMessage: String?
        @Published private(set) var authStatusMessage: String?
        @Published private(set) var shortcutSummaryText = "Shortcut configured"
        @Published private(set) var onboardingPreviewTheme: MacDictationVisualTheme = .egg
        @Published private(set) var localWhisperDownloadState: LocalWhisperDownloadState = .idle
        @Published private(set) var localWhisperDownloadFraction: Double = 0
        @Published private(set) var localWhisperBytesCompleted: Int64 = 0
        @Published private(set) var localWhisperBytesTotal: Int64 = 0

        private let coordinator: any MacPermissionsCoordinating
        private let settingsStore: DictationSettingsStore
        private let supabase: any OnboardingSupabaseAuthenticating
        private let credentialValidationService: any ProviderCredentialValidating
        private let localWhisperModelManager: LocalWhisperModelManager
        private var cancellables = Set<AnyCancellable>()
        private var lastValidatedKey: String?
        private var lastValidatedProvider: DictationProvider?

        init(
            coordinator: any MacPermissionsCoordinating,
            settingsStore: DictationSettingsStore = DictationSettingsStore(),
            supabase: (any OnboardingSupabaseAuthenticating)? = nil,
            credentialValidationService: (any ProviderCredentialValidating)? = nil,
            localWhisperModelManager: LocalWhisperModelManager = LocalWhisperModelManager()
        ) {
            self.coordinator = coordinator
            self.settingsStore = settingsStore
            self.supabase = supabase ?? SupabaseService.shared
            self.credentialValidationService = credentialValidationService ?? ProviderCredentialValidationService()
            self.localWhisperModelManager = localWhisperModelManager
            self.apiKeyProvider = settingsStore.loadProvider()
            coordinator.updates
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }

        var autoPasteStatusText: String {
            coordinator.autoPasteStatusText
        }

        var microphoneAccessStatusText: String {
            coordinator.microphoneAccessStatusText
        }

        var microphoneAccessNeedsAttention: Bool {
            coordinator.microphoneAccessNeedsAttention
        }

        var microphonePermissionActionTitle: String {
            coordinator.microphonePermissionActionTitle
        }

        var autoPasteAccessNeedsAttention: Bool {
            coordinator.autoPasteAccessNeedsAttention
        }

        var hasRequiredPermissions: Bool {
            !microphoneAccessNeedsAttention && !autoPasteAccessNeedsAttention
        }

        var onboardingStep: MacOnboardingStep {
            coordinator.onboardingStep
        }

        var onboardingMode: MacOnboardingMode? {
            coordinator.onboardingMode
        }

        var relaySessionEmail: String? {
            coordinator.relaySessionEmail
        }

        var shortcutTestDetectedPress: Bool {
            coordinator.shortcutTestDetectedPress
        }

        var shortcutTestCompletedRoundTrip: Bool {
            coordinator.shortcutTestCompletedRoundTrip
        }

        var shortcutTestPreviewText: String? {
            coordinator.shortcutTestPreviewText
        }

        var canContinueShortcutOnboarding: Bool {
            coordinator.canContinueShortcutOnboarding
        }

        var firstSuccessPreviewText: String? {
            coordinator.firstSuccessPreviewText
        }

        var firstSuccessFailureMessage: String? {
            coordinator.firstSuccessFailureMessage
        }

        var canContinueFirstSuccessOnboarding: Bool {
            coordinator.canContinueFirstSuccessOnboarding
        }

        var canSkipFirstSuccessOnboarding: Bool {
            coordinator.canSkipFirstSuccessOnboarding
        }

        var canFinishAppearanceOnboarding: Bool {
            coordinator.canFinishAppearanceOnboarding
        }

        var localWhisperDownloadPrimaryButtonTitle: String {
            switch localWhisperDownloadState {
            case .idle:
                return "Download"
            case .running(let stage):
                switch stage {
                case .checkingExistingAssets:
                    return "Checking..."
                case .downloadingModel:
                    return "Downloading..."
                case .downloadingEncoder:
                    return "Finishing up..."
                case .extractingEncoder, .warmingUp:
                    return "Finishing up..."
                case .ready:
                    return "Continue"
                }
            case .ready(_):
                return "Continue"
            case .failed(_):
                return "Try again"
            }
        }

        var isLocalWhisperDownloadRunning: Bool {
            if case .running(let stage) = localWhisperDownloadState {
                return stage != .ready
            }
            return false
        }

        var isLocalWhisperDownloadFailed: Bool {
            if case .failed = localWhisperDownloadState {
                return true
            }
            return false
        }

        var localWhisperDownloadDetailText: String {
            switch localWhisperDownloadState {
            case .idle:
                return "One click gets you ready."
            case .running(let stage):
                switch stage {
                case .checkingExistingAssets:
                    return "Working..."
                case .downloadingModel:
                    return "Downloading..."
                case .downloadingEncoder:
                    return "Almost there."
                case .extractingEncoder, .warmingUp:
                    return "Almost there."
                case .ready:
                    return "You're set."
                }
            case .ready(_):
                return "You're set."
            case .failed(let message):
                return message
            }
        }

        var localWhisperDownloadProgress: Double {
            switch localWhisperDownloadState {
            case .idle:
                return 0.0
            case .running(let stage):
                switch stage {
                case .checkingExistingAssets:
                    return 0.04
                case .downloadingModel:
                    return localWhisperDownloadFraction
                case .downloadingEncoder:
                    return 0.90
                case .extractingEncoder:
                    return 0.96
                case .warmingUp:
                    return 0.99
                case .ready:
                    return 1.0
                }
            case .ready(_):
                return 1.0
            case .failed(_):
                return 0.0
            }
        }

        var localWhisperDownloadProgressLabel: String {
            switch localWhisperDownloadState {
            case .idle:
                return "Ready to download"
            case .running(let stage):
                switch stage {
                case .checkingExistingAssets:
                    return "Preparing"
                case .downloadingModel:
                    let percentage = Int((localWhisperDownloadFraction * 100).rounded())
                    let completedMB = Double(localWhisperBytesCompleted) / 1_048_576.0
                    let totalMB = Double(localWhisperBytesTotal) / 1_048_576.0

                    if localWhisperBytesTotal > 0 {
                        return String(format: "Downloading %d%% (%.1f MB / %.1f MB)", percentage, completedMB, totalMB)
                    } else if localWhisperBytesCompleted > 0 {
                        return String(format: "Downloading (%.1f MB)", completedMB)
                    } else {
                        return percentage > 0 ? "Downloading \(percentage)%" : "Downloading"
                    }
                case .downloadingEncoder:
                    return "Finishing up"
                case .extractingEncoder:
                    return "Finishing up"
                case .warmingUp:
                    return "Optimizing"
                case .ready:
                    return "Done"
                }
            case .ready(_):
                return "Done"
            case .failed(_):
                return "Try again"
            }
        }

        var localWhisperDownloadStatusTitle: String {
            switch localWhisperDownloadState {
            case .idle:
                return "Get ready"
            case .running(let stage):
                switch stage {
                case .checkingExistingAssets:
                    return "Preparing"
                case .ready:
                    return "Ready"
                case .warmingUp:
                    return "Optimizing"
                default:
                    return "Downloading"
                }
            case .ready(_):
                return "Ready"
            case .failed(_):
                return "Failed"
            }
        }

        var localWhisperExpectedModelPath: String {
            (try? localWhisperModelManager.defaultModelURL().path)
                ?? "Unable to resolve Local Whisper model path."
        }

        var localWhisperExpectedEncoderPath: String {
            (try? localWhisperModelManager.defaultEncoderDirectoryURL().path)
                ?? "Unable to resolve Local Whisper encoder path."
        }

        var canContinueLocalWhisperDownload: Bool {
            switch localWhisperDownloadState {
            case .ready:
                return true
            case .running(let stage):
                return stage == .ready
            default:
                return false
            }
        }

        var apiKeyPrimaryButtonTitle: String {
            if isAPIKeyValidated {
                return "Continue"
            }

            return isValidatingAPIKey ? "Validating..." : "Verify Key"
        }

        var isRelaySessionActive: Bool {
            supabase.hasCurrentSession
        }

        var canSubmitEmailLogin: Bool {
            !normalizedEmail.isEmpty
                && !password.isEmpty
                && (authMode == .signIn || !confirmPassword.isEmpty)
                && !isAuthenticating
        }

        var emailPrimaryActionTitle: String {
            authMode == .signIn ? "Sign In" : "Sign Up"
        }

        var emailModeToggleTitle: String {
            authMode == .signIn ? "Create Account" : "Sign In"
        }

        var showsConfirmPasswordField: Bool {
            authMode == .signUp
        }

        func requestAutoPasteAccess() {
            coordinator.requestAutoPasteAccess()
        }

        func resolveMicrophoneAccess() {
            coordinator.resolveMicrophoneAccess()
        }

        func openAccessibilitySettings() {
            coordinator.openAccessibilitySettings()
        }

        func chooseOnboardingMode(_ mode: MacOnboardingMode) {
            clearFlowMessages()
            coordinator.chooseOnboardingMode(mode)
        }

        func prepareLocalWhisperModelIfNeeded() async {
            if case .ready = localWhisperDownloadState {
                return
            }

            if case .running = localWhisperDownloadState {
                return
            }

            do {
                localWhisperDownloadFraction = 0
                if try localWhisperModelManager.defaultModelReady() {
                    LocalWhisperModelManager.saveCustomModelPath(nil)
                    localWhisperDownloadFraction = 1
                    localWhisperDownloadState = .ready(modelPath: try localWhisperModelManager.defaultModelURL().path)
                    localWhisperModelManager.installDefaultEncoderInBackground()
                    return
                }

                localWhisperDownloadState = .running(.checkingExistingAssets)
                try await localWhisperModelManager.installDefaultModel(
                    progress: { [weak self] stage in
                        Task { @MainActor [weak self, stage] in
                            self?.localWhisperDownloadState = .running(stage)
                        }
                    },
                    downloadProgress: { [weak self] fraction, completed, total in
                        Task { @MainActor [weak self, fraction, completed, total] in
                            self?.localWhisperDownloadFraction = fraction
                            self?.localWhisperBytesCompleted = completed
                            self?.localWhisperBytesTotal = total
                        }
                    }
                )

                LocalWhisperModelManager.saveCustomModelPath(nil)
                localWhisperDownloadFraction = 1
                localWhisperDownloadState = .ready(modelPath: try localWhisperModelManager.defaultModelURL().path)

                // Trigger proactive high-priority background warm-up & encoder install
                // This shouldn't block the user from moving to the next onboarding steps.
                Task.detached(priority: .userInitiated) { [localWhisperModelManager] in
                    try? await localWhisperModelManager.installDefaultAssets()
                    try? await LocalWhisperWarmupCoordinator.shared.warmup()
                }
            } catch {
                localWhisperDownloadFraction = 0
                localWhisperDownloadState = .failed(error.localizedDescription)
            }
        }

        func handleLocalWhisperDownloadPrimaryAction() async {
            if canContinueLocalWhisperDownload {
                continueOnboarding()
                return
            }

            switch localWhisperDownloadState {
            case .idle, .failed:
                await prepareLocalWhisperModelIfNeeded()
            default:
                break
            }
        }

        func selectOnboardingAppearanceTheme(_ theme: MacDictationVisualTheme) {
            onboardingPreviewTheme = theme
            coordinator.selectOnboardingAppearanceTheme(theme)
        }

        func applyOnboardingAppearanceTheme() {
            coordinator.applyOnboardingAppearanceTheme()
        }

        func continueOnboarding() {
            coordinator.advanceOnboarding()
        }

        func retreatOnboarding() {
            clearFlowMessages()
            coordinator.retreatOnboarding()
        }

        func completeAPIKeyFlow() async {
            if isAPIKeyValidated {
                coordinator.completeAPIKeyOnboarding(provider: apiKeyProvider)
                return
            }

            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                apiKeyErrorMessage = "Please enter API Key."
                apiKeyStatusMessage = nil
                return
            }

            isValidatingAPIKey = true
            apiKeyErrorMessage = nil
            apiKeyStatusMessage = nil

            do {
                try await credentialValidationService.validateCredential(
                    apiKey: trimmedKey,
                    provider: apiKeyProvider
                )
                try settingsStore.saveAPIKey(trimmedKey, for: apiKeyProvider)
                apiKey = trimmedKey
                lastValidatedKey = trimmedKey
                lastValidatedProvider = apiKeyProvider
                isAPIKeyValidated = true
                apiKeyStatusMessage = "API Key verified."
            } catch {
                apiKeyErrorMessage = mapAPIKeyError(error)
            }

            isValidatingAPIKey = false
        }

        func signInWithEmail() async {
            authErrorMessage = nil
            authStatusMessage = nil

            do {
                let credentials = try validatedCredentials(for: .signIn)
                isAuthenticating = true
                defer { isAuthenticating = false }
                try await supabase.signIn(email: credentials.email, password: credentials.password)
                password = ""
                confirmPassword = ""
                authStatusMessage = "Login successful."
                coordinator.completeManagedOnboarding()
            } catch {
                authErrorMessage = error.localizedDescription
            }
        }

        func signUpWithEmail() async {
            authErrorMessage = nil
            authStatusMessage = nil

            do {
                let credentials = try validatedCredentials(for: .signUp)
                isAuthenticating = true
                defer { isAuthenticating = false }
                try await supabase.signUp(email: credentials.email, password: credentials.password)
                password = ""
                confirmPassword = ""

                if supabase.hasCurrentSession {
                    authStatusMessage = "Account created."
                    coordinator.completeManagedOnboarding()
                } else {
                    authStatusMessage =
                        "Account created. If email confirmation is enabled, check your inbox before signing in."
                }
            } catch {
                authErrorMessage = error.localizedDescription
            }
        }

        func toggleEmailAuthMode() {
            authMode = authMode == .signIn ? .signUp : .signIn
            password = ""
            confirmPassword = ""
            authErrorMessage = nil
            authStatusMessage = nil
        }

        func signInWithGoogle() async {
            await signInWithOAuth(provider: .google)
        }

        func signInWithApple() async {
            await signInWithOAuth(provider: .apple)
        }

        func signInWithGitHub() async {
            await signInWithOAuth(provider: .github)
        }

        func useUnavailableIdentityProvider(_ providerName: String) {
            authStatusMessage = nil
            authErrorMessage = "\(providerName) login is not yet integrated, please use Email to continue."
        }

        func continueManagedFlow() {
            authErrorMessage = nil
            authStatusMessage = nil
            coordinator.completeManagedOnboarding()
        }

        func finishOnboarding() {
            coordinator.finishOnboarding()
        }

        func updateShortcutSummary(_ shortcut: KeyboardShortcuts.Shortcut?) {
            shortcutSummaryText = shortcut.map { "\($0)" } ?? "Shortcut configured"
        }

        private func signInWithOAuth(provider: Provider) async {
            authErrorMessage = nil
            authStatusMessage = nil

            isAuthenticating = true
            defer { isAuthenticating = false }

            do {
                authStatusMessage = "Opening \(provider.displayName) sign-in..."
                try await supabase.signIn(provider: provider)
                authStatusMessage = "Login successful."
                coordinator.completeManagedOnboarding()
            } catch {
                guard !isCancellationError(error) else {
                    authStatusMessage = nil
                    return
                }

                authErrorMessage = error.localizedDescription
            }
        }

        private func clearFlowMessages() {
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = nil
            authErrorMessage = nil
            authStatusMessage = nil
        }

        private func resetAPIKeyValidationState() {
            isAPIKeyValidated = false
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = nil
            lastValidatedKey = nil
            lastValidatedProvider = nil
        }

        private var normalizedEmail: String {
            email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        private func validatedCredentials(for mode: AuthMode) throws -> (email: String, password: String) {
            let trimmedEmail = normalizedEmail

            guard !trimmedEmail.isEmpty else { throw LoginValidationError.missingEmail }
            guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
                throw LoginValidationError.invalidEmail
            }
            guard !password.isEmpty else { throw LoginValidationError.missingPassword }
            if mode == .signUp, password != confirmPassword {
                throw LoginValidationError.passwordMismatch
            }

            return (trimmedEmail, password)
        }

        private func mapAPIKeyError(_ error: Error) -> String {
            if let openAIError = error as? OpenAIError {
                switch openAIError {
                case .missingAPIKey:
                    return "Invalid Key format."
                case .api(_, let statusCode, _):
                    switch statusCode {
                    case 401, 403:
                        return "Verification failed, please check if it was copied completely."
                    case 429, 500, 502, 503, 504:
                        return "Provider is temporarily unavailable."
                    default:
                        return openAIError.localizedDescription
                    }
                case .invalidBaseURL, .invalidResponse:
                    return "Provider is temporarily unavailable."
                case .fileNotFound, .missingTranscriptionText, .missingRewriteText:
                    return openAIError.localizedDescription
                }
            }

            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                    return "Network connection error."
                default:
                    return urlError.localizedDescription
                }
            }

            return error.localizedDescription
        }

        private func isCancellationError(_ error: Error) -> Bool {
            let nsError = error as NSError
            return nsError.domain == ASWebAuthenticationSessionErrorDomain
                && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
        }
    }

    @MainActor
    protocol OnboardingSupabaseAuthenticating: AnyObject {
        var hasCurrentSession: Bool { get }
        func signIn(email: String, password: String) async throws
        func signIn(provider: Provider) async throws
        func signUp(email: String, password: String) async throws
    }
#endif
