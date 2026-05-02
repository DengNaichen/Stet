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

    override func viewWillSetupKeyboardKit() {
        let app = KeyboardApp(
            name: "StetMobile",
            appGroupId: "group.NaichengDeng.StetMobile",
            deepLinks: .init(app: "stetmobile://")
        )
        setupKeyboardKit(for: app) { _ in }
    }

    override func viewWillSetupKeyboardView() {
        // ⚠️ Don't call `super.viewWillSetupKeyboardView()` in v10 as it might conflict with custom setup.

        // SwiftUI root paints its own glass background; let it show through.
        view.backgroundColor = .clear

        setupKeyboardView { [weak self] controller in
            StetKeyboardView(controller: controller as! KeyboardViewController)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Defer polling startup until after the first render so SwiftUI hosting
        // isn't competing with timer setup during the launch window.
        startPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPolling()
    }

    internal func handleMicDown() {
        let sessionId = UUID().uuidString
        pendingSessionId = sessionId
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
              session.state == .ready,
              !session.finalText.isEmpty,
              session.sessionId != lastProcessedSessionId else {
            return
        }

        textDocumentProxy.insertText(session.finalText)
        lastProcessedSessionId = session.sessionId
        SharedDictationManager.shared.updateState(.inserted)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

}

