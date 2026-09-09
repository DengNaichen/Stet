#if os(macOS)
    import Foundation

    enum MacFeatureAvailability {
        /// Passive listening and speaker enrollment remain in the codebase, but are hidden
        /// from Settings and the menu bar until the feature is ready to ship again.
        static let isPassiveListeningVisible = false

        static func isPassiveListeningEnabled(preference: Bool) -> Bool {
            isPassiveListeningVisible && preference
        }
    }
#endif
