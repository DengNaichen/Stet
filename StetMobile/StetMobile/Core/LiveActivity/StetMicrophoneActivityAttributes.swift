import ActivityKit

nonisolated struct StetMicrophoneActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let isMicrophoneActive: Bool
    }
}
