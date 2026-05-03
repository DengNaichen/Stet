//
//  KeyboardViewController.swift
//  StetKeyboard
//
//  Created by Naicheng Deng on 2026-04-30.
//

import UIKit
import SwiftUI
import KeyboardKit

class KeyboardViewController: KeyboardInputViewController {

    private var pollTimer: Timer?
    private var lastProcessedSessionId: String?
    private var pendingSessionId: String?
    private var isWakingMainApp: Bool = false
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()

    internal func prepareButtonFeedback() {
        impactFeedback.prepare()
    }

    internal func triggerButtonFeedback() {
        impactFeedback.impactOccurred()
    }

    override func viewWillSetupKeyboardKit() {
        let app = KeyboardApp(
            name: "StetMobile",
            appGroupId: "group.NaichengDeng.StetMobile",
            deepLinks: .init(app: "stetmobile://")
        )
        setupKeyboardKit(for: app) { _ in }
    }

    override func viewWillSetupInitialKeyboardType() {
        setKeyboardType(.numeric)
    }

    override func viewWillSetupKeyboardView() {
        // ⚠️ Don't call `super.viewWillSetupKeyboardView()` in v10 as it might conflict with custom setup.

        view.backgroundColor = .clear

        // Enable KeyboardKit's built-in liquid glass button rendering on iOS 26+.
        if KeyboardContext.isLiquidGlassAvailable {
            state.keyboardContext.isLiquidGlassEnabled = true
        }

        setupKeyboardView { [weak self] controller in
            StetKeyboardView(controller: controller as! KeyboardViewController)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isWakingMainApp = false
        impactFeedback.prepare()
        notificationFeedback.prepare()
        
        // Restore pendingSessionId from shared storage in case the extension was restarted
        // during the app-switching process.
        if let savedId = SharedDictationManager.shared.getPendingKeyboardSessionId() {
            pendingSessionId = savedId
        }

        // Clear any stuck session on open.
        let activeStates: [DictationState] = [.requestStart, .launching, .warming, .requestStop, .transcribing, .ready]
        if let session = SharedDictationManager.shared.getSession(),
           activeStates.contains(session.state) {
            let appDead = !SharedDictationManager.shared.mainAppAlive(within: 2.0)
            let stale = Date().timeIntervalSince(session.updatedAt) > 10.0
            if pendingSessionId == nil || appDead || stale {
                SharedDictationManager.shared.updateState(.cancelled)
                SharedDictationManager.shared.clearPendingKeyboardSessionId()
                pendingSessionId = nil
            }
        }

        startPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPolling()
        
        // If the keyboard is closed mid-dictation (and we aren't just opening the main app),
        // we should discard the recording.
        if !isWakingMainApp,
           let session = SharedDictationManager.shared.getSession(),
           session.sessionId == pendingSessionId {
            switch session.state {
            case .requestStart, .launching, .warming, .recording, .transcribing:
                SharedDictationManager.shared.updateState(.cancelled)
                SharedDictationManager.shared.clearPendingKeyboardSessionId()
                pendingSessionId = nil
            default:
                break
            }
        }
    }

    internal func handleMicDown() {
        let sessionId = UUID().uuidString
        pendingSessionId = sessionId
        SharedDictationManager.shared.savePendingKeyboardSessionId(sessionId)
        
        let session = DictationSession(
            sessionId: sessionId,
            createdAt: Date(),
            updatedAt: Date(),
            state: .requestStart
        )
        SharedDictationManager.shared.saveSession(session)

        // If the main app's polling heartbeat is fresh, it'll pick up the
        // requestStart on its own; otherwise wake it via URL scheme.
        if !SharedDictationManager.shared.mainAppAlive(within: 0.6) {
            isWakingMainApp = true
            openMainApp(sessionId: sessionId)
        }
    }

    internal func handleMicUp() {
        guard let sessionId = pendingSessionId else { return }
        var session = SharedDictationManager.shared.getSession()
            ?? DictationSession(sessionId: sessionId, createdAt: Date(), updatedAt: Date(), state: .requestStop)
        session.state = .requestStop
        session.updatedAt = Date()
        SharedDictationManager.shared.saveSession(session)
    }

    // MARK: - Open Main App

    private func openMainApp(sessionId: String) {
        let urlString = "stetmobile://dictate?session_id=\(sessionId)"
        guard let url = URL(string: urlString) else { return }

        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = current.next
        }
    }

    // MARK: - Polling for Transcription Results

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForNewTranscription()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkForNewTranscription() {
        guard let session = SharedDictationManager.shared.getSession(),
              session.sessionId == pendingSessionId else { return }

        switch session.state {
        case .requestStop, .transcribing:
            let appDead = !SharedDictationManager.shared.mainAppAlive(within: 2.0)
            let stale = Date().timeIntervalSince(session.updatedAt) > 10.0
            if appDead || stale {
                SharedDictationManager.shared.updateState(.cancelled)
                SharedDictationManager.shared.clearPendingKeyboardSessionId()
                pendingSessionId = nil
            }
        case .ready where session.sessionId != lastProcessedSessionId:
            if !session.finalText.isEmpty {
                textDocumentProxy.insertText(session.finalText)
                notificationFeedback.notificationOccurred(.success)
            }
            lastProcessedSessionId = session.sessionId
            pendingSessionId = nil
            SharedDictationManager.shared.clearPendingKeyboardSessionId()
            SharedDictationManager.shared.updateState(.inserted)
        case .cancelled, .failed, .timeout:
            pendingSessionId = nil
            SharedDictationManager.shared.clearPendingKeyboardSessionId()
        default:
            break
        }
    }

}
