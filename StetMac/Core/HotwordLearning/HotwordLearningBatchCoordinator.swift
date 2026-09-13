#if os(macOS)
    import Foundation
    import StetAI
    import StetCore

    @MainActor
    final class HotwordLearningBatchCoordinator {
        static let batchSize = 20
        static let maximumAttempts = 3

        private let history: DictationHistoryService
        private let settings: DictationSettingsStore
        private let makeJudge: @Sendable (RewriteProviderConfiguration) -> any HotwordLearningJudging
        private var observer: NSObjectProtocol?
        private var workTask: Task<Void, Never>?
        private let reviewStore: HotwordLearningReviewStore

        init(
            history: DictationHistoryService = .shared,
            settings: DictationSettingsStore = DictationSettingsStore(),
            makeJudge: @escaping @Sendable (RewriteProviderConfiguration) -> any HotwordLearningJudging = {
                HotwordLearningJudgeFactory.make(configuration: $0)
            },
            reviewStore: HotwordLearningReviewStore = HotwordLearningReviewStore()
        ) {
            self.history = history
            self.settings = settings
            self.makeJudge = makeJudge
            self.reviewStore = reviewStore
            observer = NotificationCenter.default.addObserver(
                forName: .hotwordLearningCandidateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.candidateDidChange() }
            }
            do { try history.recoverInterruptedHotwordLearning() } catch {}
            candidateDidChange()
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            workTask?.cancel()
        }

        private func candidateDidChange() {
            guard workTask == nil else { return }
            let candidates = (try? history.fetchHotwordLearningCandidates(limit: Self.batchSize)) ?? []
            guard candidates.count == Self.batchSize else { return }
            startBatch(candidates)
        }

        private func startBatch(_ samples: [HotwordLearningHistory]) {
            guard settings.loadPersonalDictionaryEnabled(),
                let configuration = settings.loadSnapshot().rewriteProviderConfiguration
            else { return }
            let ids = samples.map(\.id)
            do { try history.markHotwordLearningInFlight(ids: ids) } catch { return }
            let request = HotwordLearningBatchRequest(histories: samples)
            let judge = makeJudge(configuration)
            workTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let response = try await judge.judge(request)
                    try history.completeHotwordLearning(ids: ids, suggestedTerms: response.unnecessaryHotwords)
                    let additions = reviewStore.addSuggestions(response.unnecessaryHotwords)
                    if !additions.isEmpty {
                        await MacDictationCompletionNotificationService.shared.notifyHotwordSuggestions(
                            count: additions.count)
                    }
                } catch {
                    let retryable = Self.isRetryable(error)
                    let attempts =
                        samples.compactMap { sample in
                            try? history.fetchRecent(limit: 300).first(where: { $0.id == sample.id })?
                                .hotwordLearningAttemptCount
                        }.compactMap { $0 }.max() ?? 1
                    if retryable && attempts < Self.maximumAttempts {
                        try? history.markHotwordLearningRetryable(ids: ids, failureCode: Self.failureCode(error))
                    } else {
                        try? history.markHotwordLearningPermanentFailure(ids: ids, failureCode: Self.failureCode(error))
                    }
                }
                workTask = nil
                candidateDidChange()
            }
        }

        private static func isRetryable(_ error: Error) -> Bool {
            if let error = error as? HotwordLearningJudgeError { return error.isRetryable }
            if error is URLError { return true }
            return false
        }

        private static func failureCode(_ error: Error) -> String {
            switch error {
            case let error as HotwordLearningJudgeError:
                switch error {
                case .unsupportedBackend: "unsupported_backend"
                case .invalidResponse: "invalid_response"
                case .api(let status, _): "http_\(status)"
                }
            case let error as URLError: "network_\(error.code.rawValue)"
            default: "unknown"
            }
        }
    }
#endif
