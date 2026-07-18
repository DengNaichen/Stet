import AVFoundation
import Combine
import CoreFoundation
import Foundation
import StetRewrite
import StetAI
import StetCore
import UIKit

@MainActor
final class SenseVoiceViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case recording
        case warming
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var transcript = ""
    @Published private(set) var partialStatus = "Loading..."
    @Published private(set) var metricsText = "Metrics will appear after decoding."
    @Published var isExternalLaunch: Bool = false
    @Published var isRecordingDone: Bool = false
    @Published private(set) var activeEngineName: String = ""

    func dismissExternalGuide() {
        isExternalLaunch = false
    }

    private var engine: ASREngine?
    private let modelManager: SenseVoiceModelManager?
    private let engineInitializationError: String?
    private var resultsListener: Task<Void, Never>?
    private let rewriteSettingsStore: RewriteSettingsStore

    private var commandPollingTimer: Timer?
    private var activeSessionId: String?

    var isRecording: Bool {
        state == .recording
    }

    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    init(rewriteSettingsStore: RewriteSettingsStore) {
        self.rewriteSettingsStore = rewriteSettingsStore

        let initialEngine: ASREngine?
        let initialModelManager: SenseVoiceModelManager?
        let initializationError: String?

        do {
            let modelManager = try SenseVoiceModelManager()
            let engine = SherpaOnnxASREngine(modelManager: modelManager)
            engine.onVolumeUpdate = { level in
                SharedDictationManager.shared.updateVolume(level)
            }
            initialEngine = engine
            initialModelManager = modelManager
            initializationError = nil
        } catch {
            initialEngine = nil
            initialModelManager = nil
            initializationError = error.localizedDescription
        }

        self.engine = initialEngine
        self.modelManager = initialModelManager
        self.engineInitializationError = initializationError
        if let initialEngine {
            attachResultsListener(to: initialEngine)
        }

        // Start polling immediately so heartbeat and incoming requestStart can be
        // picked up while bootstrap (model load) is still running in the background.
        startCommandPolling()

        Task { @MainActor in
            await self.bootstrap()
        }
        registerAudioSessionObservers()
    }

    private func attachResultsListener(to engine: ASREngine) {
        resultsListener?.cancel()
        let stream = engine.resultStream
        resultsListener = Task { @MainActor [weak self] in
            for await result in stream {
                guard !Task.isCancelled else { break }
                self?.handleASRResult(result)
            }
        }
    }

    func ensureMicAlive() {
        if case .failed = state {
            Task { @MainActor in await bootstrap() }
            return
        }
        Task {
            do {
                guard let engine else {
                    throw NSError(
                        domain: "StetMobile",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: engineInitializationError ?? "SenseVoice is unavailable."]
                    )
                }
                try await engine.prepare()
            } catch {
                await MainActor.run {
                    self.state = .failed(error.localizedDescription)
                    SharedDictationManager.shared.updateState(.failed, error: error.localizedDescription)
                }
            }
        }
    }

    private func registerAudioSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let info = note.userInfo,
                let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeRaw),
                let self
            else { return }
            if type == .ended {
                Task { @MainActor [self] in self.ensureMicAlive() }
            }
        }
        center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.ensureMicAlive() }
        }
    }

    private func bootstrap() async {
        state = .loading
        partialStatus = "Downloading SenseVoice model & requesting mic..."
        do {
            guard let engine, let modelManager else {
                throw NSError(
                    domain: "StetMobile",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: engineInitializationError ?? "SenseVoice could not be initialized."]
                )
            }

            try await requestMicrophonePermission()
            try await modelManager.downloadIfNeeded(for: SenseVoiceModelManager.modelName)
            try await engine.prepare()

            activeEngineName = engine.name
            state = .idle
            partialStatus = "Ready. Hold mic on keyboard to dictate."
        } catch {
            state = .failed(error.localizedDescription)
            partialStatus = error.localizedDescription
            SharedDictationManager.shared.updateState(.failed, error: error.localizedDescription)
        }
        checkKeyboardCommands()
    }

    private func requestMicrophonePermission() async throws {
        if #available(iOS 17.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted {
                throw NSError(
                    domain: "StetMobile",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Microphone permission was not granted."]
                )
            }
        } else {
            let granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            if !granted {
                throw NSError(
                    domain: "StetMobile",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Microphone permission was not granted."]
                )
            }
        }
    }

    func toggleRecording() {
        guard state == .idle || state == .recording else { return }
        impactGenerator.impactOccurred()
        if isRecording {
            stopEngine()
        } else {
            startEngine(sessionId: UUID().uuidString)
        }
    }

    func clearTranscript() {
        transcript = ""
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard url.scheme == "stetmobile", url.host == "dictate" else { return false }
        isExternalLaunch = true
        isRecordingDone = false
        checkKeyboardCommands()
        return true
    }

    private func startCommandPolling() {
        commandPollingTimer?.invalidate()
        commandPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.checkKeyboardCommands() }
        }
    }

    private func checkKeyboardCommands() {
        SharedDictationManager.shared.heartbeat()
        guard let session = SharedDictationManager.shared.getSession() else { return }
        switch session.state {
        case .requestStart:
            if state == .idle {
                startEngine(sessionId: session.sessionId)
            }
        case .requestStop:
            if state == .recording {
                stopEngine()
            }
        case .cancelled:
            // Keyboard was dismissed mid-recording. Stop the engine immediately and
            // reset to idle so the next .requestStart can be handled cleanly.
            engine?.stop()
            activeSessionId = nil
            state = .idle
            partialStatus = "Ready."
            SharedDictationManager.shared.updateState(.idle)
        default:
            break
        }
    }

    private func startEngine(sessionId: String) {
        activeSessionId = sessionId
        state = .recording
        partialStatus = "Recording..."

        Task { @MainActor in
            guard let engine = engine else { return }
            self.activeEngineName = engine.name

            do {
                try await engine.start(sessionId: sessionId)
            } catch {
                self.state = .failed(error.localizedDescription)
                self.partialStatus = error.localizedDescription
                self.activeSessionId = nil
                SharedDictationManager.shared.updateState(.failed, error: error.localizedDescription)
                return
            }

            // Guard against stop() racing ahead of start() completing
            guard self.activeSessionId == sessionId else { return }
            SharedDictationManager.shared.saveSession(DictationSession(
                sessionId: sessionId,
                createdAt: Date(),
                updatedAt: Date(),
                state: .recording
            ))
        }
    }

    private func stopEngine() {
        engine?.stop()
        state = .idle
        partialStatus = "Decoding..."
        SharedDictationManager.shared.updateState(.transcribing)
    }

    private func handleASRResult(_ result: ASRResult) {
        if result.isFinal {
            finalize(merged: result.text, metrics: result.metrics)
        } else {
            transcript = result.text
            SharedDictationManager.shared.updateText(partial: result.text, final: "")
        }
    }

    private func finalize(merged: String, metrics: ASRMetrics?) {
        if merged.isEmpty {
            partialStatus = "Empty result."
            SharedDictationManager.shared.updateState(.ready)
        } else {
            if let rewriteService = rewriteSettingsStore.makeRewriteServiceIfEnabled() {
                partialStatus = "Rewriting..."
                let dictionary = DictionaryModel()
                let preferredSpellings = dictionary.loadIsEnabled() ? dictionary.loadEntries() : []
                Task { @MainActor in
                    let cleaned = (try? await rewriteService.rewrite(
                        .cleanup(merged, audience: .human, preferredSpellings: preferredSpellings)
                    )) ?? merged
                    self.transcript = cleaned
                    self.partialStatus = "Finished."
                    self.notificationGenerator.notificationOccurred(.success)
                    SharedDictationManager.shared.updateText(partial: cleaned, final: cleaned)
                    SharedDictationManager.shared.updateState(.ready)
                }
            } else {
                transcript = merged
                partialStatus = "Finished."
                notificationGenerator.notificationOccurred(.success)
                SharedDictationManager.shared.updateText(partial: merged, final: merged)
                SharedDictationManager.shared.updateState(.ready)
            }
        }

        if let m = metrics {
            metricsText = String(format: "audio %.2fs, cpu %.2fs, RTF %.2f", m.audioDuration, m.cpuDuration, m.rtf)
        }

        activeSessionId = nil
        state = .idle
        isRecordingDone = true
    }
}
