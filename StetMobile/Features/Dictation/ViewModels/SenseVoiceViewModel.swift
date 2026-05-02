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

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var partialStatus = "Ready. Tap mic to start."
    @Published private(set) var metricsText = "Metrics will appear after decoding."
    @Published var isExternalLaunch: Bool = false
    @Published private(set) var activeEngineName: String = ""
    @Published var selectedEngineType: ASREngineType
    private var cancellables = Set<AnyCancellable>()
    
    func dismissExternalGuide() {
        isExternalLaunch = false
    }
    
    private var engine: ASREngine?
    private var resultsTask: Task<Void, Never>?
    private let rewriteSettingsStore: RewriteSettingsStore
    
    private var commandPollingTimer: Timer?
    private var activeSessionId: String?

    var isRecording: Bool {
        state == .recording
    }

    init(rewriteSettingsStore: RewriteSettingsStore) {
        self.rewriteSettingsStore = rewriteSettingsStore
        
        // Initialize with default engine type
        if #available(iOS 26.0, *) {
            self.selectedEngineType = .apple
        } else {
            self.selectedEngineType = .sherpa
        }
        
        self.engine = ASREngineManager.makeEngine(type: self.selectedEngineType)
        
        setupEngineSwitching()
        
        Task { @MainActor in
            await self.bootstrap()
        }
        registerAudioSessionObservers()
    }
    
    private func setupEngineSwitching() {
        $selectedEngineType
            .dropFirst()
            .sink { [weak self] newType in
                guard let self = self else { return }
                self.engine?.stop()
                self.engine = ASREngineManager.makeEngine(type: newType)
                // Clear previous engine info
                self.activeEngineName = "" 
            }
            .store(in: &cancellables)
    }

    func ensureMicAlive() {
        // Now handled by the engine or audio session observers
        // We can just trigger a bootstrap if state is failed
        if case .failed = state {
            Task { @MainActor in await bootstrap() }
        }
    }

    private func registerAudioSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Handle interruption
        }
    }

    private func bootstrap() async {
        state = .idle
        partialStatus = "Ready. Hold mic on keyboard to dictate."
        startCommandPolling()
        checkKeyboardCommands()
    }

    func toggleRecording() {
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
        checkKeyboardCommands()
        return true
    }

    private func startCommandPolling() {
        commandPollingTimer?.invalidate()
        commandPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkKeyboardCommands()
            }
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
        default:
            break
        }
    }

    private func startEngine(sessionId: String) {
        activeSessionId = sessionId
        state = .recording
        partialStatus = "Recording..."
        
        resultsTask?.cancel()
        resultsTask = Task {
            guard let engine = engine else { return }
            self.activeEngineName = engine.name
            
            // Start the engine
            do {
                try await engine.start(sessionId: sessionId)
            } catch {
                await MainActor.run {
                    self.state = .failed(error.localizedDescription)
                    SharedDictationManager.shared.updateState(.failed, error: error.localizedDescription)
                }
                return
            }
            
            // Update shared state
            SharedDictationManager.shared.saveSession(DictationSession(
                sessionId: sessionId,
                createdAt: Date(),
                updatedAt: Date(),
                state: .recording
            ))
            
            // Observe results
            for await result in engine.resultStream {
                await MainActor.run {
                    self.handleASRResult(result)
                }
            }
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
            // AI Rewrite logic
            if let rewriteService = rewriteSettingsStore.makeRewriteServiceIfEnabled() {
                partialStatus = "Rewriting..."
                Task {
                    let cleaned = (try? await rewriteService.rewrite(.cleanup(merged, audience: .human))) ?? merged
                    await MainActor.run {
                        self.transcript = cleaned
                        self.partialStatus = "Finished."
                        SharedDictationManager.shared.updateText(partial: cleaned, final: cleaned)
                        SharedDictationManager.shared.updateState(.ready)
                    }
                }
            } else {
                transcript = merged
                partialStatus = "Finished."
                SharedDictationManager.shared.updateText(partial: merged, final: merged)
                SharedDictationManager.shared.updateState(.ready)
            }
        }
        
        if let m = metrics {
            metricsText = String(format: "audio %.2fs, cpu %.2fs, RTF %.2f", m.audioDuration, m.cpuDuration, m.rtf)
        }
        
        activeSessionId = nil
        state = .idle
    }
}



