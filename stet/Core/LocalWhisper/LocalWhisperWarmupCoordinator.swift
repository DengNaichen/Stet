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
        private let keepAliveWarmupInterval: TimeInterval
        private let sampleURLProvider: @Sendable () -> URL?
        private let serviceFactory: @Sendable (LocalWhisperModelManager) throws -> any AudioFileTranscriptionService
        private var hasActivated = false
        private var warmService: (any AudioFileTranscriptionService)?
        private var warmedModelPath: String?
        private var wakeObserver: NSObjectProtocol?
        private var scheduledWarmupTask: Task<Void, Never>?
        private var keepAliveTask: Task<Void, Never>?

        init(
            modelManager: LocalWhisperModelManager = LocalWhisperModelManager(),
            startupWarmupDelay: TimeInterval = 3,
            keepAliveWarmupInterval: TimeInterval = 240,
            sampleURLProvider: (@Sendable () -> URL?)? = nil,
            serviceFactory: (@Sendable (LocalWhisperModelManager) throws -> any AudioFileTranscriptionService)? = nil
        ) {
            self.modelManager = modelManager
            self.startupWarmupDelay = startupWarmupDelay
            self.keepAliveWarmupInterval = keepAliveWarmupInterval
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
            startKeepAliveWarmupLoop()
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
                logMessage: "Explicit Local Whisper warmup finished and engine persisted.")
        }

        private func scheduleWarmup(after seconds: TimeInterval) {
            scheduledWarmupTask?.cancel()
            scheduledWarmupTask = Task { [weak self] in
                let delayNanoseconds = UInt64(seconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayNanoseconds)

                guard !Task.isCancelled, let self else { return }

                do {
                    try await self.performWarmupIfPossible(
                        logMessage: "Local Whisper warmup finished and engine persisted."
                    )
                } catch {
                    self.logger.error("Local Whisper warmup failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        private func startKeepAliveWarmupLoop() {
            guard keepAliveTask == nil else { return }

            keepAliveTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }

                    let delayNanoseconds = UInt64(self.keepAliveWarmupInterval * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delayNanoseconds)

                    guard !Task.isCancelled else { return }

                    do {
                        try await self.performWarmupIfPossible(
                            logMessage: "Local Whisper keep-alive warmup refreshed the shared engine."
                        )
                    } catch {
                        self.logger.error(
                            "Local Whisper keep-alive warmup failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
        }

        private func performWarmupIfPossible(logMessage: StaticString) async throws {
            guard let sampleURL = sampleURLProvider() else {
                return
            }

            let modelURL: URL
            switch try modelManager.status() {
            case .ready(let localURL):
                modelURL = localURL
            case .missing, .runtimeUnavailable:
                return
            }

            let modelPath = modelURL.standardizedFileURL.path
            let service: any AudioFileTranscriptionService
            if let warmService, warmedModelPath == modelPath {
                service = warmService
            } else {
                service = try serviceFactory(modelManager)
                self.warmService = service
                self.warmedModelPath = modelPath
            }

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
