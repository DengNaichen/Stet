import Foundation

enum TranslationTargetLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case english
    case chineseSimplified
    case japanese
    case korean
    case spanish
    case french
    case german

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .english:
            return "English"
        case .chineseSimplified:
            return "Chinese (Simplified)"
        case .japanese:
            return "Japanese"
        case .korean:
            return "Korean"
        case .spanish:
            return "Spanish"
        case .french:
            return "French"
        case .german:
            return "German"
        }
    }

    nonisolated var instructionName: String {
        switch self {
        case .english:
            return "English"
        case .chineseSimplified:
            return "Simplified Chinese"
        case .japanese:
            return "Japanese"
        case .korean:
            return "Korean"
        case .spanish:
            return "Spanish"
        case .french:
            return "French"
        case .german:
            return "German"
        }
    }
}

struct OpenAIConfiguration: Sendable {
    var apiKey: String
    var baseURL: URL
    var transcriptionModel: String
    var translationModel: String
    var rewriteModel: String
    var organizationID: String?
    var projectID: String?

    nonisolated init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        transcriptionModel: String = "gpt-4o-mini-transcribe",
        translationModel: String = "gpt-5-mini",
        rewriteModel: String = "gpt-5-mini",
        organizationID: String? = nil,
        projectID: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.transcriptionModel = transcriptionModel
        self.translationModel = translationModel
        self.rewriteModel = rewriteModel
        self.organizationID = organizationID
        self.projectID = projectID
    }
}
