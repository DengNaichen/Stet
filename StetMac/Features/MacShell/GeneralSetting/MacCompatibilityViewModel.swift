#if os(macOS)
    import Combine
    import Foundation

    /// Presentation facade over the app compatibility list refresh.
    @MainActor
    final class MacCompatibilityViewModel: ObservableObject {
        private let store: AppCompatibilityStore
        private var cancellable: AnyCancellable?

        init(store: AppCompatibilityStore) {
            self.store = store
            cancellable = store.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
        }

        var refreshState: AppCompatibilityStore.RefreshState { store.refreshState }

        func refresh() async {
            await store.refresh()
        }
    }
#endif
