#if os(macOS)
    import Combine
    import FluidAudio
    import Foundation
    import os

    /// Single point of ownership for the loaded NVIDIA Parakeet ASR engine.
    ///
    /// Mirrors `LocalWhisperContextManager`: holds the loaded `AsrManager` for
    /// the whole app, exposes `isModelLoaded` / `isModelLoading` for UI, and
    /// releases everything between recordings via `cleanupResources()` so memory
    /// drops back to baseline. The transcription service reuses the loaded
    /// manager when present and falls back to a transient one otherwise.
    @MainActor
    final class LocalParakeetContextManager: ObservableObject {
        static let shared = LocalParakeetContextManager()

        @Published private(set) var isModelLoaded = false
        @Published private(set) var isModelLoading = false

        private(set) var asrManager: AsrManager?
        private(set) var loadedVersion: AsrModelVersion?

        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "LocalParakeetContext"
        )

        init() {}

        /// Loads `version` into the shared engine slot if nothing is loaded. The
        /// closure is only called when a fresh `AsrManager` needs to be built so
        /// callers don't pay the cost in the hot path. Idempotent if a manager
        /// is already loaded; switch versions by calling `cleanupResources()` first.
        func loadModel(
            version: AsrModelVersion,
            modelLoader: @Sendable (AsrModelVersion) async throws -> AsrModels
        ) async throws {
            guard asrManager == nil else { return }

            isModelLoading = true
            defer { isModelLoading = false }

            do {
                let models = try await modelLoader(version)
                let manager = AsrManager(config: .default)
                try await manager.initialize(models: models)
                asrManager = manager
                loadedVersion = version
                isModelLoaded = true
            } catch {
                asrManager = nil
                loadedVersion = nil
                isModelLoaded = false
                throw error
            }
        }

        /// Returns the loaded manager when it matches `version`, else nil.
        func managerIfLoaded(matching version: AsrModelVersion) -> AsrManager? {
            guard let asrManager, loadedVersion == version else { return nil }
            return asrManager
        }

        /// Releases the loaded ASR manager and resets state. Safe to call when
        /// nothing is loaded.
        func cleanupResources() async {
            guard let asrManager else { return }
            logger.notice("LocalParakeetContextManager.cleanupResources: releasing ASR manager")
            await asrManager.cleanup()
            self.asrManager = nil
            self.loadedVersion = nil
            self.isModelLoaded = false
            logger.notice("LocalParakeetContextManager.cleanupResources: completed")
        }
    }
#endif
