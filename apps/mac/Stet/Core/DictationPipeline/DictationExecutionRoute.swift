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

enum DictationExecutionRoute: Sendable {
    struct Direct: Sendable {
        let configuration: OpenAIConfiguration
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

        if snapshot.executionMode.requiresLocalAPIKey, snapshot.providerConfiguration == nil {
            throw OpenAIError.missingAPIKey(provider: snapshot.provider)
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

            guard let configuration = snapshot.providerConfiguration else {
                throw OpenAIError.missingAPIKey(provider: snapshot.provider)
            }

            return .direct(
                .init(
                    configuration: configuration,
                    rewriteEnabled: snapshot.isRewriteEnabled,
                    languageMode: snapshot.dictationLanguageMode,
                    preferredSpellings: snapshot.personalDictionary
                )
            )
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
            guard let configuration = snapshot.providerConfiguration else {
                throw OpenAIError.missingAPIKey(provider: snapshot.provider)
            }

            return .direct(
                .init(
                    configuration: configuration,
                    rewriteEnabled: snapshot.isRewriteEnabled,
                    languageMode: snapshot.dictationLanguageMode,
                    preferredSpellings: snapshot.personalDictionary
                )
            )
        }
    }
}
