import Foundation

public enum RewriteModel: String, CaseIterable, Identifiable, Sendable {
    // OpenAI Models
    case gpt54Mini = "gpt-5.4-mini-2026-04-12"
    case gpt54Nano = "gpt-5.4-nano-2026-03-17"

    // Groq Models
    case gptOss20b = "openai/gpt-oss-20b"
    case llama3_70b = "llama-3.3-70b-specdec"
    case mixtral8x7b = "mixtral-8x7b-32768"
    case gemma2_9b = "gemma2-9b-it"

    // Chinese Provider Models
    case deepseekV4Flash = "deepseek-v4-flash"
    case deepseekV4Pro = "deepseek-v4-pro"
    case qwenMax = "qwen-max"
    case qwenPlus = "qwen-plus"
    case qwenTurbo = "qwen-turbo"
    case glm4 = "glm-4"
    case glm4Air = "glm-4-air"
    case glm4Flash = "glm-4-flash"
    case doubao = "doubao-seed-1-6-251015"

    // Google Models
    case gemini31FlashLitePreview = "gemini-3.1-flash-lite-preview"
    case gemini25FlashLite = "gemini-2.5-flash-lite"

    // Anthropic Models
    case claude46Sonnet = "claude-sonnet-4-6"
    case claude46Haiku = "claude-haiku-4-6"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gpt54Mini: return NSLocalizedString("GPT-5.4 Mini", comment: "")
        case .gpt54Nano: return NSLocalizedString("GPT-5.4 Nano (Default)", comment: "")
        case .gptOss20b: return NSLocalizedString("GPT-OSS 20B (Default)", comment: "")
        case .llama3_70b: return NSLocalizedString("Llama 3.3 70B", comment: "")
        case .mixtral8x7b: return NSLocalizedString("Mixtral 8x7B", comment: "")
        case .gemma2_9b: return NSLocalizedString("Gemma 2 9B", comment: "")
        case .deepseekV4Flash: return NSLocalizedString("DeepSeek V4 Flash (Default)", comment: "")
        case .deepseekV4Pro: return NSLocalizedString("DeepSeek V4 Pro", comment: "")
        case .qwenMax: return NSLocalizedString("Qwen Max", comment: "")
        case .qwenPlus: return NSLocalizedString("Qwen Plus", comment: "")
        case .qwenTurbo: return NSLocalizedString("Qwen Turbo", comment: "")
        case .glm4: return NSLocalizedString("GLM-4", comment: "")
        case .glm4Air: return NSLocalizedString("GLM-4 Air", comment: "")
        case .glm4Flash: return NSLocalizedString("GLM-4 Flash", comment: "")
        case .doubao: return NSLocalizedString("Doubao Seed 1.6", comment: "")
        case .gemini31FlashLitePreview: return NSLocalizedString("Gemini 3.1 Flash Lite Preview", comment: "")
        case .gemini25FlashLite: return NSLocalizedString("Gemini 2.5 Flash Lite", comment: "")
        case .claude46Sonnet: return NSLocalizedString("Claude 4.6 Sonnet", comment: "")
        case .claude46Haiku: return NSLocalizedString("Claude 4.6 Haiku", comment: "")
        }
    }

    public static func availableModels(for provider: DictationProvider) -> [RewriteModel] {
        switch provider {
        case .openAI:
            return [.gpt54Nano, .gpt54Mini]
        case .groq:
            return [.gptOss20b, .llama3_70b, .mixtral8x7b, .gemma2_9b]
        case .deepSeek:
            return [.deepseekV4Flash, .deepseekV4Pro]
        case .qwen:
            return [.qwenMax, .qwenPlus, .qwenTurbo]
        case .glm:
            return [.glm4, .glm4Air, .glm4Flash]
        case .doubao:
            return [.doubao]
        case .google:
            return [.gemini31FlashLitePreview, .gemini25FlashLite]
        case .anthropic:
            return [.claude46Sonnet, .claude46Haiku]
        case .appleIntelligence:
            return []
        }
    }

    public static func `default`(for provider: DictationProvider) -> RewriteModel {
        switch provider {
        case .openAI: return .gpt54Nano
        case .groq: return .gptOss20b
        case .deepSeek: return .deepseekV4Flash
        case .qwen: return .qwenPlus
        case .glm: return .glm4
        case .doubao: return .doubao
        case .google: return .gemini31FlashLitePreview
        case .anthropic: return .claude46Haiku
        case .appleIntelligence: return .gpt54Nano
        }
    }
}
