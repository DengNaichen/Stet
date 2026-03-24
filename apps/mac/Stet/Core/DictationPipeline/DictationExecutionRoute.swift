import Foundation

struct RelayAuthenticationContext: Sendable, Equatable {
    let functionsBaseURL: URL
    let publishableKey: String
    let accessToken: String

    nonisolated var relayBaseURL: URL {
        functionsBaseURL.appendingPathComponent("relay/v1")
    }
}

enum AIExecutionError: LocalizedError, Equatable {
    case managedRequiresAuthenticatedSession
    case relayInvocationFailed(statusCode: Int?, message: String, requestID: String?)

    nonisolated var errorDescription: String? {
        switch self {
        case .managedRequiresAuthenticatedSession:
            return "Managed Relay requires a signed-in Stet account."
        case .relayInvocationFailed(let statusCode, let message, let requestID):
            let requestIDSuffix = requestID.map { " Request ID: \($0)." } ?? ""

            if let statusCode {
                return "Managed Relay error (\(statusCode)): \(message).\(requestIDSuffix)"
            }

            return "Managed Relay error: \(message).\(requestIDSuffix)"
        }
    }
}

enum ProviderConfigurationError: LocalizedError, Equatable {
    case missingRequirements([ProviderConfigurationRequirement])
    case unsupportedProviderCombination(DictationProviderPair)

    nonisolated var errorDescription: String? {
        switch self {
        case .missingRequirements(let requirements):
            let normalizedRequirements = requirements.sorted {
                if $0.step == $1.step {
                    return $0.provider.displayName < $1.provider.displayName
                }

                return $0.step.rawValue < $1.step.rawValue
            }

            guard let firstRequirement = normalizedRequirements.first else {
                return "Provider configuration is incomplete."
            }

            if normalizedRequirements.count == 1 {
                return
                    "Add a \(firstRequirement.provider.displayName) API key to use \(firstRequirement.provider.displayName) for \(firstRequirement.step.displayName)."
            }

            let detail =
                normalizedRequirements
                .map { "\($0.provider.displayName) for \($0.step.displayName)" }
                .joined(separator: ", ")
            return "Add API keys for \(detail) before starting dictation."
        case .unsupportedProviderCombination:
            return "OpenAI transcription with Groq rewrite is not supported as a default BYOK pair on Mac."
        }
    }
}

enum DictationExecutionRoute: Sendable {
    struct Direct: Sendable {
        let transcriptionConfiguration: OpenAIConfiguration
        let rewriteConfiguration: OpenAIConfiguration?
        let rewriteEnabled: Bool
        let languageMode: DictationLanguageMode
        let preferredSpellings: [String]
    }

    struct Relay: Sendable {
        let authentication: RelayAuthenticationContext
        let rewriteEnabled: Bool
        let languageMode: DictationLanguageMode
        let preferredSpellings: [String]
    }

    case direct(Direct)
    case relay(Relay)
}

enum DictationExecutionRouteResolver {
    nonisolated static func resolve(
        snapshot: DictationSettingsSnapshot,
        relayAuthentication: RelayAuthenticationContext?
    ) throws -> DictationExecutionRoute {
        if snapshot.executionMode.requiresAuthenticatedSession, relayAuthentication == nil {
            throw AIExecutionError.managedRequiresAuthenticatedSession
        }

        switch snapshot.executionMode {
        case .automatic:
            if let relayAuthentication {
                return .relay(
                    .init(
                        authentication: relayAuthentication,
                        rewriteEnabled: snapshot.isRewriteEnabled,
                        languageMode: snapshot.dictationLanguageMode,
                        preferredSpellings: snapshot.personalDictionary
                    )
                )
            }

            return .direct(try resolveDirectRoute(snapshot: snapshot))
        case .managed:
            guard let relayAuthentication else {
                throw AIExecutionError.managedRequiresAuthenticatedSession
            }

            return .relay(
                .init(
                    authentication: relayAuthentication,
                    rewriteEnabled: snapshot.isRewriteEnabled,
                    languageMode: snapshot.dictationLanguageMode,
                    preferredSpellings: snapshot.personalDictionary
                )
            )
        case .byok:
            return .direct(try resolveDirectRoute(snapshot: snapshot))
        }
    }

    nonisolated private static func resolveDirectRoute(
        snapshot: DictationSettingsSnapshot
    ) throws -> DictationExecutionRoute.Direct {
        if snapshot.isRewriteEnabled && !OpenAIConfiguration.isSupportedProviderPair(snapshot.providerPair) {
            throw ProviderConfigurationError.unsupportedProviderCombination(snapshot.providerPair)
        }

        let missingRequirements = snapshot.requiredProviderRequirements().filter { requirement in
            switch requirement.step {
            case .transcription:
                return snapshot.transcriptionProviderConfiguration == nil
            case .rewrite:
                return snapshot.rewriteProviderConfiguration == nil
            }
        }

        if !missingRequirements.isEmpty {
            throw ProviderConfigurationError.missingRequirements(missingRequirements)
        }

        guard let transcriptionConfiguration = snapshot.transcriptionProviderConfiguration else {
            throw ProviderConfigurationError.missingRequirements([
                ProviderConfigurationRequirement(
                    step: .transcription,
                    provider: snapshot.transcriptionProvider
                )
            ])
        }

        return .init(
            transcriptionConfiguration: transcriptionConfiguration,
            rewriteConfiguration: snapshot.isRewriteEnabled ? snapshot.rewriteProviderConfiguration : nil,
            rewriteEnabled: snapshot.isRewriteEnabled,
            languageMode: snapshot.dictationLanguageMode,
            preferredSpellings: snapshot.personalDictionary
        )
    }
}
