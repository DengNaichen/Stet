import Foundation
import Testing
@testable import StetMobile

struct FunASRProtocolTests {
    @Test func buildsRegionalWorkspaceEndpointsAndAuthorizationHeader() throws {
        let beijing = try FunASRConfiguration(
            region: .beijing,
            workspaceID: "workspace-123",
            apiKey: "secret-key"
        )
        let singapore = try FunASRConfiguration(
            region: .singapore,
            workspaceID: "workspace-123",
            apiKey: "secret-key"
        )

        #expect(
            beijing.endpoint.absoluteString
                == "wss://workspace-123.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference"
        )
        #expect(
            singapore.endpoint.absoluteString
                == "wss://workspace-123.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/inference"
        )
        #expect(beijing.webSocketRequest.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
    }

    @Test func runTaskAndFinishTaskMessagesMatchTheRealtimeProtocol() throws {
        let run = try jsonObject(FunASRProtocol.runTaskData(taskID: "task-1"))
        let runHeader = try #require(run["header"] as? [String: Any])
        let runPayload = try #require(run["payload"] as? [String: Any])
        let parameters = try #require(runPayload["parameters"] as? [String: Any])

        #expect(runHeader["action"] as? String == "run-task")
        #expect(runHeader["task_id"] as? String == "task-1")
        #expect(runHeader["streaming"] as? String == "duplex")
        #expect(runPayload["task_group"] as? String == "audio")
        #expect(runPayload["task"] as? String == "asr")
        #expect(runPayload["function"] as? String == "recognition")
        #expect(runPayload["model"] as? String == "fun-asr-realtime")
        #expect(parameters["format"] as? String == "pcm")
        #expect(parameters["sample_rate"] as? Int == 16_000)
        #expect(parameters["heartbeat"] as? Bool == true)

        let finish = try jsonObject(FunASRProtocol.finishTaskData(taskID: "task-1"))
        let finishHeader = try #require(finish["header"] as? [String: Any])
        #expect(finishHeader["action"] as? String == "finish-task")
        #expect(finishHeader["task_id"] as? String == "task-1")
        #expect(finishHeader["streaming"] as? String == "duplex")
    }

    @Test func parsesLifecycleSentenceAndHeartbeatEvents() throws {
        #expect(try parse(#"{"header":{"event":"task-started"}}"#) == .taskStarted)
        #expect(
            try parse(
                #"{"header":{"event":"result-generated"},"payload":{"output":{"sentence":{"sentence_id":7,"text":"hello","sentence_end":false}}}}"#
            ) == .sentence(.init(id: 7, text: "hello", isFinal: false))
        )
        #expect(
            try parse(
                #"{"header":{"event":"result-generated"},"payload":{"output":{"sentence":{"heartbeat":true}}}}"#
            ) == .heartbeat
        )
        #expect(try parse(#"{"header":{"event":"task-finished"}}"#) == .taskFinished)
    }

    @Test func mapsServerFailuresWithoutExposingRawMessages() throws {
        #expect(
            try parse(
                #"{"header":{"event":"task-failed","error_code":"InvalidApiKey","error_message":"raw secret-bearing response"}}"#
            ) == .taskFailed(.authenticationFailed)
        )
        #expect(
            try parse(
                #"{"header":{"event":"task-failed","error_code":"InternalError","error_message":"raw server stack"}}"#
            ) == .taskFailed(.serviceUnavailable)
        )
    }

    @Test func accumulatesSentenceFinalsWithoutEndingTheSession() {
        var accumulator = FunASRTranscriptAccumulator()

        #expect(
            accumulator.update(with: .init(id: 1, text: "hello", isFinal: false))
                == "hello"
        )
        #expect(
            accumulator.update(with: .init(id: 1, text: "hello world", isFinal: true))
                == "hello world"
        )
        #expect(
            accumulator.update(with: .init(id: 2, text: "again", isFinal: false))
                == "hello world again"
        )
        #expect(
            accumulator.update(with: .init(id: 2, text: "中文", isFinal: true))
                == "hello world中文"
        )
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func parse(_ json: String) throws -> FunASRServerEvent {
        try FunASRProtocol.parseServerEvent(Data(json.utf8))
    }
}
