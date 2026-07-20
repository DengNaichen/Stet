#if os(macOS)
    import Combine
    import Foundation
    import os

    /// Single point of ownership for the loaded Local Whisper engine.
    ///
    /// Mirrors VoiceInk's `WhisperModelManager`: holds one engine for the whole
    /// app, exposes `isModelLoaded` / `loadedModelPath` / `isModelLoading` for UI,
    /// and releases the engine between recordings via `cleanupResources()`.
    @MainActor
    final class LocalWhisperContextManager: ObservableObject {
        static let shared = LocalWhisperContextManager()

        @Published private(set) var isModelLoaded = false
        @Published private(set) var loadedModelPath: String?
        @Published private(set) var isModelLoading = false

        private(set) var engine: (any LocalWhisperEngine)?

        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "LocalWhisperContext"
        )

        init() {}

        /// Loads `modelURL` into the shared engine slot if nothing is loaded.
        ///
        /// Matches `WhisperModelManager.loadModel`: idempotent if a context is
        /// already present, regardless of whether it's the same model. If you
        /// need to switch models, call `cleanupResources()` first.
        func loadModel(
            modelURL: URL,
            engineFactory: @Sendable (URL) throws -> any LocalWhisperEngine
        ) async throws {
            guard engine == nil else { return }

            isModelLoading = true
            defer { isModelLoading = false }

            do {
                let newEngine = try engineFactory(modelURL)
                try await newEngine.prewarm()
                engine = newEngine
                loadedModelPath = modelURL.standardizedFileURL.path
                isModelLoaded = true
            } catch {
                engine = nil
                loadedModelPath = nil
                isModelLoaded = false
                throw error
            }
        }

        /// Returns the loaded engine when it was built from `modelURL`, else nil.
        /// Callers use the returned engine directly; non-matches fall through to
        /// a transient engine.
        func engineIfLoaded(matching modelURL: URL) -> (any LocalWhisperEngine)? {
            guard let engine, let loadedModelPath else { return nil }
            guard loadedModelPath == modelURL.standardizedFileURL.path else { return nil }
            return engine
        }

        /// Releases the loaded engine and resets state. Safe to call when
        /// nothing is loaded.
        func cleanupResources() async {
            guard let engine else { return }
            logger.notice("LocalWhisperContextManager.cleanupResources: releasing whisper context")
            await engine.releaseResources()
            self.engine = nil
            self.loadedModelPath = nil
            self.isModelLoaded = false
            logger.notice("LocalWhisperContextManager.cleanupResources: completed")
        }
    }
#endif
