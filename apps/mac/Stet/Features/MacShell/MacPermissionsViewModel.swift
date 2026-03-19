#if os(macOS)
import Combine
import Foundation
import KeyboardShortcuts
import OpenAI

@MainActor
final class MacPermissionsViewModel: ObservableObject {
    private enum LoginValidationError: LocalizedError {
        case missingEmail
        case invalidEmail
        case missingPassword

        var errorDescription: String? {
            switch self {
            case .missingEmail:
                return "请输入邮箱地址。"
            case .invalidEmail:
                return "请输入有效的邮箱地址。"
            case .missingPassword:
                return "请输入密码。"
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
    @Published private(set) var isAuthenticating = false
    @Published private(set) var authErrorMessage: String?
    @Published private(set) var authStatusMessage: String?
    @Published private(set) var shortcutSummaryText = "当前快捷键已配置"

    private let coordinator: any MacPermissionsCoordinating
    private let settingsStore: DictationSettingsStore
    private let supabase: SupabaseService
    private let apiKeyValidationService: APIKeyValidationService
    private var cancellables = Set<AnyCancellable>()
    private var lastValidatedKey: String?
    private var lastValidatedProvider: DictationProvider?

    init(
        coordinator: any MacPermissionsCoordinating,
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        supabase: SupabaseService? = nil,
        apiKeyValidationService: APIKeyValidationService? = nil
    ) {
        self.coordinator = coordinator
        self.settingsStore = settingsStore
        self.supabase = supabase ?? .shared
        self.apiKeyValidationService = apiKeyValidationService ?? APIKeyValidationService()
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

    var apiKeyPrimaryButtonTitle: String {
        if isAPIKeyValidated {
            return "继续"
        }

        return isValidatingAPIKey ? "验证中..." : "验证 Key"
    }

    var isRelaySessionActive: Bool {
        supabase.currentSession != nil
    }

    var canSubmitEmailLogin: Bool {
        !normalizedEmail.isEmpty && !password.isEmpty && !isAuthenticating
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
            apiKeyErrorMessage = "请输入 API Key。"
            apiKeyStatusMessage = nil
            return
        }

        isValidatingAPIKey = true
        apiKeyErrorMessage = nil
        apiKeyStatusMessage = nil

        do {
            try await apiKeyValidationService.validate(
                apiKey: trimmedKey,
                provider: apiKeyProvider
            )
            try settingsStore.saveAPIKey(trimmedKey, for: apiKeyProvider)
            apiKey = trimmedKey
            lastValidatedKey = trimmedKey
            lastValidatedProvider = apiKeyProvider
            isAPIKeyValidated = true
            apiKeyStatusMessage = "API Key 已验证。"
        } catch {
            apiKeyErrorMessage = mapAPIKeyError(error)
        }

        isValidatingAPIKey = false
    }

    func signInWithEmail() async {
        authErrorMessage = nil
        authStatusMessage = nil

        do {
            let credentials = try validatedCredentials()
            isAuthenticating = true
            defer { isAuthenticating = false }
            try await supabase.signIn(email: credentials.email, password: credentials.password)
            password = ""
            authStatusMessage = "登录成功。"
            coordinator.completeManagedOnboarding()
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    func useUnavailableIdentityProvider(_ providerName: String) {
        authStatusMessage = nil
        authErrorMessage = "\(providerName) 登录暂时还没接入，请先用 Email 继续。"
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
        shortcutSummaryText = shortcut.map { "\($0)" } ?? "当前快捷键已配置"
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

    private func validatedCredentials() throws -> (email: String, password: String) {
        let trimmedEmail = normalizedEmail

        guard !trimmedEmail.isEmpty else { throw LoginValidationError.missingEmail }
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            throw LoginValidationError.invalidEmail
        }
        guard !password.isEmpty else { throw LoginValidationError.missingPassword }

        return (trimmedEmail, password)
    }

    private func mapAPIKeyError(_ error: Error) -> String {
        if let openAIError = error as? OpenAIError {
            switch openAIError {
            case .missingAPIKey:
                return "Key 格式不正确。"
            case .api(_, let statusCode, _):
                switch statusCode {
                case 401, 403:
                    return "验证失败，请检查是否复制完整。"
                case 429, 500, 502, 503, 504:
                    return "Provider 暂时不可用。"
                default:
                    return openAIError.localizedDescription
                }
            case .invalidBaseURL, .invalidResponse:
                return "Provider 暂时不可用。"
            case .fileNotFound, .missingTranscriptionText, .missingRewriteText, .missingTranslationText:
                return openAIError.localizedDescription
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                return "网络连接异常。"
            default:
                return urlError.localizedDescription
            }
        }

        return error.localizedDescription
    }
}

struct APIKeyValidationService: Sendable {
    func validate(apiKey: String, provider: DictationProvider) async throws {
        let configuration = OpenAIConfiguration(apiKey: apiKey, provider: provider)
        let requestContext = try OpenAISDKClientFactory(configuration: configuration)
            .makeRequestContext(timeoutInterval: 15)

        do {
            let response = try await requestContext.client.responses.createResponse(
                query: CreateModelResponseQuery(
                    input: .inputItemList([
                        .inputMessage(
                            EasyInputMessage(
                                role: .user,
                                content: .textInput("Reply with ok.")
                            )
                        )
                    ]),
                    model: configuration.rewriteModel,
                    store: configuration.supportsResponsesStore ? false : nil
                )
            )

            guard response.stetOutputText != nil else {
                throw OpenAIError.invalidResponse(provider: provider)
            }
        } catch {
            throw requestContext.mapError(error)
        }
    }
}
#endif
