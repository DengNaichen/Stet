import Foundation

nonisolated enum FunASRError: LocalizedError, Equatable, Sendable {
    case missingConfiguration
    case authenticationFailed
    case connectionFailed
    case serviceUnavailable
    case audioUnavailable
    case audioQueueOverflow
    case taskStartTimedOut
    case taskFinishTimedOut
    case invalidServerResponse

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Complete the FunASR region, Workspace ID, and API key settings first."
        case .authenticationFailed:
            "FunASR authentication failed. Check the API key and Workspace ID."
        case .connectionFailed:
            "FunASR lost its network connection. Please try again."
        case .serviceUnavailable:
            "FunASR could not complete this transcription. Please try again."
        case .audioUnavailable:
            "The microphone audio could not be prepared for FunASR."
        case .audioQueueOverflow:
            "The network is too slow to keep up with the microphone. This recording was stopped."
        case .taskStartTimedOut:
            "FunASR did not start within 10 seconds. Please try again."
        case .taskFinishTimedOut:
            "FunASR did not finish within 15 seconds. Please try again."
        case .invalidServerResponse:
            "FunASR returned an unreadable response. Please try again."
        }
    }
}

nonisolated struct MobileASREngineFailure: Sendable {
    let sessionId: String?
    let message: String
}

protocol MobileASREngineFailureReporting: AnyObject {
    var failureStream: AsyncStream<MobileASREngineFailure> { get }
}

nonisolated struct FunASRSentence: Equatable, Sendable {
    let id: Int
    let text: String
    let isFinal: Bool
}

nonisolated enum FunASRServerEvent: Equatable, Sendable {
    case taskStarted
    case sentence(FunASRSentence)
    case heartbeat
    case taskFinished
    case taskFailed(FunASRError)
}

nonisolated enum FunASRProtocol {
    static let model = "fun-asr-realtime"
    static let sampleRate = 16_000
    static let audioFrameBytes = 3_200

    static func runTaskData(taskID: String) throws -> Data {
        try JSONEncoder().encode(
            ClientMessage(
                header: .init(action: "run-task", taskID: taskID),
                payload: .init(
                    taskGroup: "audio",
                    task: "asr",
                    function: "recognition",
                    model: model,
                    parameters: .init(format: "pcm", sampleRate: sampleRate, heartbeat: true),
                    input: .init()
                )
            )
        )
    }

    static func finishTaskData(taskID: String) throws -> Data {
        try JSONEncoder().encode(
            ClientMessage(
                header: .init(action: "finish-task", taskID: taskID),
                payload: .init(input: .init())
            )
        )
    }

    static func parseServerEvent(_ data: Data) throws -> FunASRServerEvent {
        let envelope: ServerEnvelope
        do {
            envelope = try JSONDecoder().decode(ServerEnvelope.self, from: data)
        } catch {
            throw FunASRError.invalidServerResponse
        }

        switch envelope.header.event {
        case "task-started":
            return .taskStarted
        case "result-generated":
            guard let sentence = envelope.payload?.output?.sentence else {
                throw FunASRError.invalidServerResponse
            }
            if sentence.heartbeat == true {
                return .heartbeat
            }
            guard let id = sentence.sentenceID,
                let text = sentence.text,
                let isFinal = sentence.sentenceEnd
            else {
                throw FunASRError.invalidServerResponse
            }
            return .sentence(.init(id: id, text: text, isFinal: isFinal))
        case "task-finished":
            return .taskFinished
        case "task-failed":
            return .taskFailed(mapServiceFailure(code: envelope.header.errorCode))
        default:
            throw FunASRError.invalidServerResponse
        }
    }

    private static func mapServiceFailure(code: String?) -> FunASRError {
        let normalizedCode = code?.lowercased() ?? ""
        if normalizedCode.contains("auth")
            || normalizedCode.contains("token")
            || normalizedCode.contains("api_key")
            || normalizedCode.contains("apikey")
            || normalizedCode.contains("workspace")
        {
            return .authenticationFailed
        }
        return .serviceUnavailable
    }
}

nonisolated private struct ClientMessage: Encodable {
    struct Header: Encodable {
        let action: String
        let taskID: String
        let streaming = "duplex"

        enum CodingKeys: String, CodingKey {
            case action
            case taskID = "task_id"
            case streaming
        }
    }

    struct Payload: Encodable {
        struct Parameters: Encodable {
            let format: String
            let sampleRate: Int
            let heartbeat: Bool

            enum CodingKeys: String, CodingKey {
                case format
                case sampleRate = "sample_rate"
                case heartbeat
            }
        }

        struct EmptyInput: Encodable {}

        let taskGroup: String?
        let task: String?
        let function: String?
        let model: String?
        let parameters: Parameters?
        let input: EmptyInput

        init(
            taskGroup: String? = nil,
            task: String? = nil,
            function: String? = nil,
            model: String? = nil,
            parameters: Parameters? = nil,
            input: EmptyInput
        ) {
            self.taskGroup = taskGroup
            self.task = task
            self.function = function
            self.model = model
            self.parameters = parameters
            self.input = input
        }

        enum CodingKeys: String, CodingKey {
            case taskGroup = "task_group"
            case task
            case function
            case model
            case parameters
            case input
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(taskGroup, forKey: .taskGroup)
            try container.encodeIfPresent(task, forKey: .task)
            try container.encodeIfPresent(function, forKey: .function)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encodeIfPresent(parameters, forKey: .parameters)
            try container.encode(input, forKey: .input)
        }
    }

    let header: Header
    let payload: Payload
}

nonisolated private struct ServerEnvelope: Decodable {
    struct Header: Decodable {
        let event: String
        let errorCode: String?

        enum CodingKeys: String, CodingKey {
            case event
            case errorCode = "error_code"
        }
    }

    struct Payload: Decodable {
        struct Output: Decodable {
            struct Sentence: Decodable {
                let sentenceID: Int?
                let text: String?
                let heartbeat: Bool?
                let sentenceEnd: Bool?

                enum CodingKeys: String, CodingKey {
                    case sentenceID = "sentence_id"
                    case text
                    case heartbeat
                    case sentenceEnd = "sentence_end"
                }
            }

            let sentence: Sentence?
        }

        let output: Output?
    }

    let header: Header
    let payload: Payload?
}

nonisolated struct FunASRTranscriptAccumulator: Sendable {
    private var sentenceOrder: [Int] = []
    private var committed: [Int: String] = [:]
    private var partials: [Int: String] = [:]

    mutating func update(with sentence: FunASRSentence) -> String {
        if !sentenceOrder.contains(sentence.id) {
            sentenceOrder.append(sentence.id)
        }
        if sentence.isFinal {
            committed[sentence.id] = sentence.text
            partials.removeValue(forKey: sentence.id)
        } else {
            partials[sentence.id] = sentence.text
        }
        return text
    }

    var text: String {
        sentenceOrder.reduce(into: "") { result, id in
            let segment = committed[id] ?? partials[id] ?? ""
            result = Self.join(result, segment)
        }
    }

    private static func join(_ left: String, _ right: String) -> String {
        let left = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty else { return right }
        guard !right.isEmpty else { return left }
        guard let last = left.last, let first = right.first else { return left + right }

        if isCJK(last) || isCJK(first) || closingPunctuation.contains(first)
            || openingPunctuation.contains(last)
        {
            return left + right
        }
        return left + " " + right
    }

    private static let closingPunctuation = CharacterSet(
        charactersIn: ".,!?;:%)]}>，。！？；：、）》】』”"
    )
    private static let openingPunctuation = CharacterSet(
        charactersIn: "([{<（《【『“\""
    )

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                0x3040...0x30FF, 0xAC00...0xD7AF:
                true
            default:
                false
            }
        }
    }
}

private extension CharacterSet {
    nonisolated func contains(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(contains)
    }
}
