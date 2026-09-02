import Foundation

public enum RewriteModel: String, CaseIterable, Identifiable, Sendable {
    case gpt56Luna = "gpt-5.6-luna"
    case gptOss20b = "openai/gpt-oss-20b"
    case deepseekV4Flash = "deepseek-v4-flash"
    case qwen35Flash = "qwen3.5-flash"
    case glm47Flash = "glm-4.7-flash"
    case doubaoSeed20Mini = "doubao-seed-2-0-mini-260428"
    case gemini37Flash = "gemini-3.7-flash"
    case claudeHaiku45 = "claude-haiku-4-5"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gpt56Luna: return NSLocalizedString("GPT-5.6 Luna", comment: "")
        case .gptOss20b: return NSLocalizedString("GPT-OSS 20B", comment: "")
        case .deepseekV4Flash: return NSLocalizedString("DeepSeek V4 Flash", comment: "")
        case .qwen35Flash: return NSLocalizedString("Qwen 3.5 Flash", comment: "")
        case .glm47Flash: return NSLocalizedString("GLM-4.7 Flash", comment: "")
        case .doubaoSeed20Mini: return NSLocalizedString("Doubao Seed 2.0 Mini", comment: "")
        case .gemini37Flash: return NSLocalizedString("Gemini 3.7 Flash", comment: "")
        case .claudeHaiku45: return NSLocalizedString("Claude Haiku 4.5", comment: "")
        }
    }

    public static func availableModels(for provider: DictationProvider) -> [RewriteModel] {
        switch provider {
        case .openAI:
            return [.gpt56Luna]
        case .groq:
            return []
        case .deepSeek:
            return [.deepseekV4Flash]
        case .qwen:
            return [.qwen35Flash]
        case .glm:
            return [.glm47Flash]
        case .doubao:
            return []
        case .google:
            return [.gemini37Flash]
        case .anthropic:
            return []
        case .appleIntelligence:
            return []
        }
    }

    public static func `default`(for provider: DictationProvider) -> RewriteModel {
        switch provider {
        case .openAI: return .gpt56Luna
        case .groq: return .gptOss20b
        case .deepSeek: return .deepseekV4Flash
        case .qwen: return .qwen35Flash
        case .glm: return .glm47Flash
        case .doubao: return .doubaoSeed20Mini
        case .google: return .gemini37Flash
        case .anthropic: return .claudeHaiku45
        case .appleIntelligence: return .gpt56Luna
        }
    }
}
