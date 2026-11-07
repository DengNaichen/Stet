#if os(macOS)
    import Combine
    import Foundation
    import Observation

    /// Presentation facade over the app compatibility list refresh.
    @MainActor
    @Observable
    final class MacCompatibilityViewModel {
        private let store: AppCompatibilityStore
        @ObservationIgnored private var cancellable: AnyCancellable?

        init(store: AppCompatibilityStore) {
            self.store = store
            refreshState = store.refreshState
            cancellable = store.$refreshState
                .sink { [weak self] state in
                    self?.refreshState = state
                }
        }

        private(set) var refreshState: AppCompatibilityStore.RefreshState

        func refresh() async {
            await store.refresh()
        }
    }
#endif
