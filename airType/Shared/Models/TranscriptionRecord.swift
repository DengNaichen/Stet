import Foundation

enum TranscriptionRecordKind: String, CaseIterable, Codable, Sendable {
    case dictation
    case translation
    case rewrite

    var title: String {
        switch self {
        case .dictation:
            return "Dictation"
        case .translation:
            return "Translation"
        case .rewrite:
            return "Rewrite"
        }
    }
}

enum TranscriptionRecordSource: String, Codable, Sendable {
    case speech
    case selection

    var title: String {
        switch self {
        case .speech:
            return "Speech"
        case .selection:
            return "Selected Text"
        }
    }
}

enum HistoryRetentionPeriod: String, CaseIterable, Identifiable, Codable, Sendable {
    case sevenDays
    case thirtyDays
    case forever

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sevenDays:
            return "7 Days"
        case .thirtyDays:
            return "30 Days"
        case .forever:
            return "Forever"
        }
    }

    func includes(_ date: Date, relativeTo now: Date = .now) -> Bool {
        switch self {
        case .sevenDays:
            return date >= now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .thirtyDays:
            return date >= now.addingTimeInterval(-30 * 24 * 60 * 60)
        case .forever:
            return true
        }
    }
}

struct TranscriptionRecordMetadata: Equatable, Codable, Sendable {
    let kind: TranscriptionRecordKind
    let source: TranscriptionRecordSource
    let transcriptionProvider: String?
    let transcriptionModel: String?
    let translationModel: String?
    let rewriteModel: String?
    let targetLanguage: String?
    let focusedAppName: String?
    let focusedBundleID: String?
    let matchedAppBranchRuleName: String?
    let matchedURLPattern: String?

    init(
        kind: TranscriptionRecordKind = .dictation,
        source: TranscriptionRecordSource = .speech,
        transcriptionProvider: String? = nil,
        transcriptionModel: String? = nil,
        translationModel: String? = nil,
        rewriteModel: String? = nil,
        targetLanguage: String? = nil,
        focusedAppName: String? = nil,
        focusedBundleID: String? = nil,
        matchedAppBranchRuleName: String? = nil,
        matchedURLPattern: String? = nil
    ) {
        self.kind = kind
        self.source = source
        self.transcriptionProvider = transcriptionProvider
        self.transcriptionModel = transcriptionModel
        self.translationModel = translationModel
        self.rewriteModel = rewriteModel
        self.targetLanguage = targetLanguage
        self.focusedAppName = focusedAppName
        self.focusedBundleID = focusedBundleID
        self.matchedAppBranchRuleName = matchedAppBranchRuleName
        self.matchedURLPattern = matchedURLPattern
    }
}

struct TranscriptionRecord: Identifiable, Equatable, Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case createdAt
        case metadata
    }

    let id: UUID
    let text: String
    let createdAt: Date
    let metadata: TranscriptionRecordMetadata

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = .now,
        metadata: TranscriptionRecordMetadata = .init()
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.metadata = metadata
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        metadata = try container.decodeIfPresent(TranscriptionRecordMetadata.self, forKey: .metadata) ?? .init()
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(metadata, forKey: .metadata)
    }
}
