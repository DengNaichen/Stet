import Foundation

enum ProviderConfigurationError: LocalizedError, Equatable {
    case missingRequirements([ProviderConfigurationRequirement])

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
        }
    }
}

enum DictationExecutionRoute: Sendable {
    struct Direct: Sendable {
        let rewriteConfiguration: RewriteProviderConfiguration?
        let rewriteEnabled: Bool
        let languageMode: DictationLanguageMode
        let preferredSpellings: [String]
    }

    case direct(Direct)
}

enum DictationExecutionRouteResolver {
    nonisolated static func resolve(
        snapshot: DictationSettingsSnapshot
    ) throws -> DictationExecutionRoute {
        return .direct(try resolveDirectRoute(snapshot: snapshot))
    }

    nonisolated private static func resolveDirectRoute(
        snapshot: DictationSettingsSnapshot
    ) throws -> DictationExecutionRoute.Direct {
        if !snapshot.isRewriteEnabled {
            return .init(
                rewriteConfiguration: nil,
                rewriteEnabled: false,
                languageMode: snapshot.dictationLanguageMode,
                preferredSpellings: snapshot.personalDictionary
            )
        }

        let missingRequirements = snapshot.requiredProviderRequirements().filter { requirement in
            switch requirement.step {
            case .transcription:
                return false
            case .rewrite:
                return snapshot.rewriteProviderConfiguration == nil
            }
        }

        guard missingRequirements.isEmpty, let rewriteConfiguration = snapshot.rewriteProviderConfiguration else {
            // If rewrite is enabled but config is missing, fallback to direct route WITHOUT rewrite
            // instead of throwing a blocking configuration error.
            return .init(
                rewriteConfiguration: nil,
                rewriteEnabled: false,
                languageMode: snapshot.dictationLanguageMode,
                preferredSpellings: snapshot.personalDictionary
            )
        }

        return .init(
            rewriteConfiguration: rewriteConfiguration,
            rewriteEnabled: snapshot.isRewriteEnabled,
            languageMode: snapshot.dictationLanguageMode,
            preferredSpellings: snapshot.personalDictionary
        )
    }
}
