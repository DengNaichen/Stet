#if os(macOS)
    import AppKit
    import Foundation
    import StetASR
    import os

    /// Silently prepares and keeps the Fun-ASR Nano ANE encoder resident across
    /// app launch, system wake, and version/OS updates without blocking foreground dictation.
    @MainActor
    final class FunASRNanoANEGuardian {
        private let modelManager: FunASRNanoModelManager
        private let installer: any ANEModelInstalling
        private let contextManager: FunASRNanoContextManager
        private let notificationCenter: NotificationCenter
        private let startupDelay: Duration
        private let sleep: @Sendable (Duration) async throws -> Void
        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "FunASRNanoANEGuardian"
        )

        private var wakeObserver: NSObjectProtocol?
        private var maintenanceTask: Task<Void, Never>?
        private var pendingWakeRefresh = false

        init(
            modelManager: FunASRNanoModelManager = FunASRNanoModelManager(),
            installer: any ANEModelInstalling,
            contextManager: FunASRNanoContextManager = .shared,
            notificationCenter: NotificationCenter? = nil,
            startupDelay: Duration = .seconds(1),
            sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
        ) {
            self.modelManager = modelManager
            self.installer = installer
            self.contextManager = contextManager
            self.notificationCenter = notificationCenter ?? NSWorkspace.shared.notificationCenter
            self.startupDelay = startupDelay
            self.sleep = sleep
        }

        deinit {
            maintenanceTask?.cancel()
            if let wakeObserver {
                notificationCenter.removeObserver(wakeObserver)
            }
        }

        func start() {
            guard ANEModelReadiness.supported, wakeObserver == nil else { return }
            wakeObserver = notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleRefresh(isWake: true, delay: .milliseconds(250))
                }
            }
            scheduleRefresh(isWake: false, delay: startupDelay)
        }

        func stop() {
            maintenanceTask?.cancel()
            maintenanceTask = nil
            pendingWakeRefresh = false
            if let wakeObserver {
                notificationCenter.removeObserver(wakeObserver)
                self.wakeObserver = nil
            }
        }

        func refreshNow(isWake: Bool = false) async {
            scheduleRefresh(isWake: isWake, delay: .zero)
            await maintenanceTask?.value
        }

        private func scheduleRefresh(isWake: Bool, delay: Duration) {
            guard ANEModelReadiness.supported else { return }
            if maintenanceTask != nil {
                if isWake { pendingWakeRefresh = true }
                return
            }

            let modelManager = self.modelManager
            let installer = self.installer
            let contextManager = self.contextManager
            let sleep = self.sleep
            let logger = self.logger

            maintenanceTask = Task(priority: .utility) { [weak self] in
                if delay > .zero {
                    do {
                        try await sleep(delay)
                    } catch {
                        await MainActor.run { self?.didFinishRefreshPass() }
                        return
                    }
                }
                guard !Task.isCancelled else {
                    await MainActor.run { self?.didFinishRefreshPass() }
                    return
                }

                await Self.performSilentRefresh(
                    isWake: isWake,
                    modelManager: modelManager,
                    installer: installer,
                    contextManager: contextManager,
                    logger: logger
                )
                await MainActor.run { self?.didFinishRefreshPass() }
            }
        }

        private func didFinishRefreshPass() {
            maintenanceTask = nil
            if pendingWakeRefresh {
                pendingWakeRefresh = false
                scheduleRefresh(isWake: true, delay: .zero)
            }
        }

        private nonisolated static func performSilentRefresh(
            isWake: Bool,
            modelManager: FunASRNanoModelManager,
            installer: any ANEModelInstalling,
            contextManager: FunASRNanoContextManager,
            logger: Logger
        ) async {
            guard modelManager.isModelDownloaded(),
                let files = try? modelManager.modelFiles()
            else {
                return
            }
            let directory = files.encoder.deletingLastPathComponent()

            if ANEModelReadiness.needsSilentPreparation(in: directory) {
                logger.notice("Fun-ASR Nano ANE receipt invalidated by OS or app update; preparing silently.")
                do {
                    try await installer.prepareInstalled { _ in }
                } catch is CancellationError {
                    return
                } catch ANEModelInstallError.busy {
                    return
                } catch {
                    logger.warning(
                        "Silent Fun-ASR Nano ANE re-preparation failed: \(error.localizedDescription, privacy: .public)"
                    )
                    return
                }
            }

            guard !Task.isCancelled else { return }
            if isWake {
                await contextManager.handleSystemWake(in: directory)
            } else {
                await contextManager.preloadResidentEncoder(in: directory)
            }
        }
    }
#endif
