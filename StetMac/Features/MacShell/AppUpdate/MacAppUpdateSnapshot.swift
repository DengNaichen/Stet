#if os(macOS)
    struct MacAppUpdateSnapshot: Equatable {
        var state: MacAppUpdateState
        var isConfigured: Bool
        var canCheckForUpdates: Bool
        var automaticallyChecksForUpdates: Bool

        var isChecking: Bool { state == .checking }
    }
#endif
