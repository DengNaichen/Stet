#if os(macOS)
    import Foundation
    import FoundationModels
    import StetAI
    import StetCore

    @available(macOS 26.0, *)
    @Generable
    private struct AppleHotwordLearningOutput {
        @Guide(description: "Exact supplied hot words that clearly did not need hot-word assistance")
        let unnecessaryHotwords: [String]
    }

    @available(macOS 26.0, *)
    struct AppleIntelligenceHotwordLearningJudgeService: HotwordLearningJudging {
        func judge(_ request: HotwordLearningBatchRequest) async throws -> HotwordLearningBatchResponse {
            guard !request.histories.isEmpty,
                request.histories.count <= HotwordLearningBatchValidator.maximumBatchSize
            else { throw HotwordLearningValidationError.invalidBatchSize }
            guard case .available = SystemLanguageModel.default.availability else {
                throw HotwordLearningJudgeError.unsupportedBackend
            }
            let payload = try JSONEncoder().encode(request)
            guard let prompt = String(data: payload, encoding: .utf8) else {
                throw HotwordLearningJudgeError.invalidResponse
            }
            let session = LanguageModelSession(
                model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
                instructions: CloudHotwordLearningJudgeService.systemPrompt
            )
            let generated = try await session.respond(
                to: Prompt(prompt),
                generating: AppleHotwordLearningOutput.self
            )
            let response = HotwordLearningBatchResponse(
                version: request.version,
                unnecessaryHotwords: generated.content.unnecessaryHotwords
            )
            _ = try HotwordLearningBatchValidator.validate(response, for: request)
            return response
        }
    }

    struct UnavailableHotwordLearningJudgeService: HotwordLearningJudging {
        func judge(_: HotwordLearningBatchRequest) async throws -> HotwordLearningBatchResponse {
            throw HotwordLearningJudgeError.unsupportedBackend
        }
    }

    enum HotwordLearningJudgeFactory {
        static func make(configuration: RewriteProviderConfiguration) -> any HotwordLearningJudging {
            if case .appleIntelligence = configuration.backend {
                if #available(macOS 26.0, *) {
                    return AppleIntelligenceHotwordLearningJudgeService()
                }
                return UnavailableHotwordLearningJudgeService()
            }
            return CloudHotwordLearningJudgeService(configuration: configuration)
        }
    }
#endif
