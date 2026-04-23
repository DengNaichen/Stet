#if os(macOS)
    import AppKit
    import Foundation
    import os

    @MainActor
    final class LocalWhisperWarmupCoordinator {
        static let shared = LocalWhisperWarmupCoordinator()

        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "LocalWhisperWarmup"
        )
        private let modelManager: LocalWhisperModelManager
        private let startupWarmupDelay: TimeInterval
        private let sampleURLProvider: @Sendable () -> URL?
        private let serviceFactory: @Sendable (LocalWhisperModelManager) throws -> any AudioFileTranscriptionService
        private var hasActivated = false
        private var wakeObserver: NSObjectProtocol?
        private var scheduledWarmupTask: Task<Void, Never>?

        init(
            modelManager: LocalWhisperModelManager = LocalWhisperModelManager(),
            startupWarmupDelay: TimeInterval = 3,
            sampleURLProvider: (@Sendable () -> URL?)? = nil,
            serviceFactory: (@Sendable (LocalWhisperModelManager) throws -> any AudioFileTranscriptionService)? = nil
        ) {
            self.modelManager = modelManager
            self.startupWarmupDelay = startupWarmupDelay
            self.sampleURLProvider =
                sampleURLProvider
                ?? {
                    Bundle.main.url(
                        forResource: "DictationStartSoft",
                        withExtension: "wav"
                    )
                }
            self.serviceFactory =
                serviceFactory
                ?? { manager in
                    try LocalWhisperTranscriptionService(modelManager: manager)
                }
        }

        func activateIfNeeded() {
            guard !hasActivated else { return }
            hasActivated = true

            scheduleWarmup(after: startupWarmupDelay)
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleWarmup(after: self?.startupWarmupDelay ?? 3)
                }
            }
        }

        func warmup() async throws {
            try await performWarmupIfPossible(
                logMessage: "Explicit Local Whisper warmup finished.")
        }

        private func scheduleWarmup(after seconds: TimeInterval) {
            scheduledWarmupTask?.cancel()
            scheduledWarmupTask = Task { [weak self] in
                let delayNanoseconds = UInt64(seconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayNanoseconds)

                guard !Task.isCancelled, let self else { return }

                do {
                    try await self.performWarmupIfPossible(
                        logMessage: "Local Whisper warmup finished."
                    )
                } catch {
                    self.logger.error("Local Whisper warmup failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        private func performWarmupIfPossible(logMessage: StaticString) async throws {
            guard let sampleURL = sampleURLProvider() else {
                return
            }

            switch try modelManager.status() {
            case .ready:
                break
            case .missing, .runtimeUnavailable:
                return
            }

            let service = try serviceFactory(modelManager)
            _ = try await service.transcribe(
                audioFileAt: sampleURL,
                languageCode: nil,
                prompt: nil,
                audioDurationSeconds: nil
            )
            logger.debug("\(String(describing: logMessage), privacy: .public)")
        }
    }
#endif
