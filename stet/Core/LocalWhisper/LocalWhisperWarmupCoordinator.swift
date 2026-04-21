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
        private var hasActivated = false
        private var wakeObserver: NSObjectProtocol?

        init(modelManager: LocalWhisperModelManager = LocalWhisperModelManager()) {
            self.modelManager = modelManager
        }

        func activateIfNeeded() {
            guard !hasActivated else { return }
            hasActivated = true

            scheduleWarmup(after: 3)
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleWarmup(after: 3)
                }
            }
        }

        func warmup() async throws {
            guard
                let sampleURL = Bundle.main.url(
                    forResource: "DictationStartSoft",
                    withExtension: "wav"
                )
            else {
                return
            }

            let service = try LocalWhisperTranscriptionService(modelManager: modelManager)
            _ = try await service.transcribe(
                audioFileAt: sampleURL,
                languageCode: nil,
                prompt: nil,
                audioDurationSeconds: nil
            )
            logger.debug("Explicit Local Whisper warmup finished.")
        }

        private func scheduleWarmup(after seconds: TimeInterval) {
            Task.detached(priority: .utility) { [modelManager, logger] in
                let delayNanoseconds = UInt64(seconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayNanoseconds)

                guard !Task.isCancelled else { return }

                do {
                    switch try modelManager.status() {
                    case .ready:
                        break
                    case .missing, .runtimeUnavailable:
                        return
                    }

                    guard
                        let sampleURL = Bundle.main.url(
                            forResource: "DictationStartSoft",
                            withExtension: "wav"
                        )
                    else {
                        return
                    }

                    let service = try LocalWhisperTranscriptionService(modelManager: modelManager)
                    _ = try await service.transcribe(
                        audioFileAt: sampleURL,
                        languageCode: nil,
                        prompt: nil,
                        audioDurationSeconds: nil
                    )
                    logger.debug("Local Whisper warmup finished.")
                } catch {
                    logger.error("Local Whisper warmup failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
#endif
