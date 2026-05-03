//
//  KeyboardViewController.swift
//  StetKeyboard
//
//  Created by Naicheng Deng on 2026-04-30.
//

import UIKit
import SwiftUI
import Combine
import KeyboardKit

enum KeyboardButtonState: Equatable {
    case idle
    case pending      // requestStart / launching / warming
    case recording
    case processing   // requestStop / transcribing / ready
}

class KeyboardViewController: KeyboardInputViewController, ObservableObject {

    @Published var buttonState: KeyboardButtonState = .idle
    @Published var processingStartDate: Date? = nil

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
        pendingSessionId = SharedDictationManager.shared.getPendingKeyboardSessionId()

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
            case .requestStart, .launching, .warming, .recording, .requestStop, .transcribing:
                cancelOurSession()
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

        // Optimistic update so the button responds before the next tick.
        publishState(.pending)
    }

    internal func handleMicUp() {
        guard let sessionId = pendingSessionId else { return }
        var session = SharedDictationManager.shared.getSession()
            ?? DictationSession(sessionId: sessionId, createdAt: Date(), updatedAt: Date(), state: .requestStop)
        session.state = .requestStop
        session.updatedAt = Date()
        SharedDictationManager.shared.saveSession(session)

        publishState(.processing)
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

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func tick() {
        let session = SharedDictationManager.shared.getSession()

        // Ownership check: anything that isn't ours renders as idle. If a not-ours
        // session is stuck active and the main app is dead/silent, sweep it so it
        // doesn't haunt subsequent keyboard instances.
        guard let session, session.sessionId == pendingSessionId else {
            if let session, isActiveState(session.state) {
                let appDead = !SharedDictationManager.shared.mainAppAlive(within: 2.0)
                let stale = Date().timeIntervalSince(session.updatedAt) > 10.0
                if appDead || stale {
                    SharedDictationManager.shared.updateState(.cancelled)
                }
            }
            publishState(.idle)
            return
        }

        switch session.state {
        case .idle:
            publishState(.idle)

        case .requestStart, .launching, .warming:
            publishState(.pending)

        case .recording:
            publishState(.recording)

        case .requestStop, .transcribing:
            let appDead = !SharedDictationManager.shared.mainAppAlive(within: 2.0)
            let stale = Date().timeIntervalSince(session.updatedAt) > 10.0
            if appDead || stale {
                cancelOurSession()
                publishState(.idle)
            } else {
                publishState(.processing)
            }

        case .ready:
            if session.sessionId != lastProcessedSessionId {
                insertTranscription(session)
            }
            publishState(.idle)

        case .inserted, .cancelled, .failed, .timeout:
            cleanupSession()
            publishState(.idle)
        }
    }

    private func isActiveState(_ s: DictationState) -> Bool {
        switch s {
        case .requestStart, .launching, .warming, .recording, .requestStop, .transcribing, .ready:
            return true
        default:
            return false
        }
    }

    private func publishState(_ state: KeyboardButtonState) {
        if state == .processing && buttonState != .processing {
            processingStartDate = Date()
        } else if state != .processing && processingStartDate != nil {
            processingStartDate = nil
        }
        if buttonState != state {
            buttonState = state
        }
    }

    private func insertTranscription(_ session: DictationSession) {
        if !session.finalText.isEmpty {
            textDocumentProxy.insertText(session.finalText)
            notificationFeedback.notificationOccurred(.success)
        }
        lastProcessedSessionId = session.sessionId
        pendingSessionId = nil
        SharedDictationManager.shared.clearPendingKeyboardSessionId()
        SharedDictationManager.shared.updateState(.inserted)
    }

    private func cancelOurSession() {
        SharedDictationManager.shared.updateState(.cancelled)
        SharedDictationManager.shared.clearPendingKeyboardSessionId()
        pendingSessionId = nil
    }

    private func cleanupSession() {
        pendingSessionId = nil
        SharedDictationManager.shared.clearPendingKeyboardSessionId()
    }

}
