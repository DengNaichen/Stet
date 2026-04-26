#if os(macOS)
    import Combine
    import Foundation

    @MainActor
    final class TrialStore: ObservableObject {
        static let shared = TrialStore()
        static let freeLimit = 30

        private let usedKey = "com.stet.transcriptionsUsed"

        @Published private(set) var transcriptionsUsed: Int

        init() {
            transcriptionsUsed = UserDefaults.standard.integer(forKey: usedKey)
        }

        var isExpired: Bool { transcriptionsUsed >= Self.freeLimit }
        var remaining: Int { max(0, Self.freeLimit - transcriptionsUsed) }
        var isNearingLimit: Bool { remaining <= 5 && !isExpired }

        func record() {
            transcriptionsUsed += 1
            UserDefaults.standard.set(transcriptionsUsed, forKey: usedKey)
        }

        #if DEBUG
            func reset() {
                transcriptionsUsed = 0
                UserDefaults.standard.set(0, forKey: usedKey)
            }
        #endif
    }
#endif
