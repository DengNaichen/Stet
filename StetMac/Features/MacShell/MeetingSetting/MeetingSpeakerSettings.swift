#if os(macOS)
    import Combine
    import Foundation

    @MainActor
    final class MeetingSpeakerSettings: ObservableObject {
        enum State: Equatable {
            case missing, checking, downloading(Double), validating, ready, failed(String)
        }

        @Published private(set) var state: State = .missing
        @Published private(set) var isEnabled: Bool
        @Published var showsDownloadPrompt = false
        private let store: MeetingSpeakerModelStore
        private let defaults: UserDefaults
        private var task: Task<Void, Never>?
        private var generation = UUID()
        static let preferenceKey = "meetingSeparateSpeakers"

        init(store: MeetingSpeakerModelStore, defaults: UserDefaults = .standard) {
            self.store = store
            self.defaults = defaults
            self.isEnabled = defaults.bool(forKey: Self.preferenceKey)
        }

        var isWorking: Bool {
            switch state {
            case .checking, .downloading, .validating: true
            default: false
            }
        }

        func requestEnabled(_ enabled: Bool) {
            if !enabled {
                cancelDownload()
                setEnabled(false)
            } else if state == .ready {
                setEnabled(true)
            } else {
                showsDownloadPrompt = true
            }
        }

        func refresh() {
            guard !isWorking else { return }
            guard store.isComplete else { state = .missing; return }
            let token = UUID()
            generation = token
            state = .checking
            task = Task { [weak self, store] in
                do {
                    try await store.checkReady()
                    guard let self, self.generation == token else { return }
                    self.state = .ready
                } catch {
                    guard let self, self.generation == token else { return }
                    self.state = .failed(error.localizedDescription)
                }
            }
        }

        func downloadAndEnable() {
            guard !isWorking else { return }
            showsDownloadPrompt = false
            setEnabled(false)
            let token = UUID()
            generation = token
            state = .downloading(0)
            task = Task { [weak self, store] in
                do {
                    try await store.prepare { [weak self] fraction in
                        Task { @MainActor in
                            guard let self, self.generation == token, self.isWorking else { return }
                            self.state = fraction >= 1 ? .validating : .downloading(fraction)
                        }
                    }
                    try Task.checkCancellation()
                    guard let self, self.generation == token else { return }
                    self.state = .ready
                    self.setEnabled(true)
                } catch {
                    guard let self, self.generation == token else { return }
                    self.state = .failed(error.localizedDescription)
                }
            }
        }

        func cancelDownload() {
            generation = UUID()
            task?.cancel()
            task = nil
            if isWorking { state = .missing }
        }

        /// Revalidate before starting; never downloads or silently changes the user's preference.
        func isReadyForMeeting() async -> Bool {
            guard !isWorking else { return false }
            do {
                try await store.checkReady()
                state = .ready
                return true
            } catch {
                state = .failed(error.localizedDescription)
                return false
            }
        }

        private func setEnabled(_ enabled: Bool) {
            isEnabled = enabled
            defaults.set(enabled, forKey: Self.preferenceKey)
        }
    }
#endif
