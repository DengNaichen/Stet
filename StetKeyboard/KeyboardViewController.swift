//
//  KeyboardViewController.swift
//  StetKeyboard
//
//  Created by Naicheng Deng on 2026-04-30.
//

import UIKit
import SwiftUI

class KeyboardViewController: UIInputViewController {

    private var pollTimer: Timer?
    private var lastProcessedSessionId: String?
    private var pendingSessionId: String?

    override func updateViewConstraints() {
        super.updateViewConstraints()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Give the system an explicit input view height so it doesn't reject
        // the keyboard for missing intrinsic size during first activation.
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 260)
        heightConstraint.priority = .required - 1
        heightConstraint.isActive = true

        let keyboardView = KeyboardView(
            onMicDown: { [weak self] in
                self?.handleMicDown()
            },
            onMicUp: { [weak self] in
                self?.handleMicUp()
            },
            onKeyTap: { [weak self] text in
                if text == "__DONE__" {
                    self?.insertFinalResult()
                } else {
                    self?.textDocumentProxy.insertText(text)
                }
            },
            onBackspace: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            },
            onReturn: { [weak self] in
                self?.textDocumentProxy.insertText("\n")
            },
            onNextKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            }
        )
        let hostingController = UIHostingController(rootView: keyboardView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.leftAnchor.constraint(equalTo: view.leftAnchor),
            hostingController.view.rightAnchor.constraint(equalTo: view.rightAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
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

    private func handleMicDown() {
        let sessionId = UUID().uuidString
        pendingSessionId = sessionId
        let session = DictationSession(
            sessionId: sessionId,
            createdAt: Date(),
            updatedAt: Date(),
            state: .requestStart
        )
        SharedDictationManager.shared.saveSession(session)

        // Safety: if main app isn't alive in background to pick this up,
        // fall back to launching it via URL scheme.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let current = SharedDictationManager.shared.getSession()
            if current?.sessionId == sessionId, current?.state == .requestStart {
                self.openMainApp(sessionId: sessionId)
            }
        }
    }

    private func handleMicUp() {
        guard let sessionId = pendingSessionId else { return }
        var session = SharedDictationManager.shared.getSession()
            ?? DictationSession(sessionId: sessionId, createdAt: Date(), updatedAt: Date(), state: .requestStop)
        session.state = .requestStop
        session.updatedAt = Date()
        SharedDictationManager.shared.saveSession(session)
    }

    // MARK: - Open Main App

    private func openMainApp(sessionId: String) {
        let urlString = "testvoice://dictate?session_id=\(sessionId)"
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
        // Poll every 0.5 seconds for results from the main app
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

        // Insert the text
        textDocumentProxy.insertText(session.finalText)
        
        // Mark as processed to prevent duplicate insertion
        lastProcessedSessionId = session.sessionId
        
        // Update state to inserted in shared storage
        SharedDictationManager.shared.updateState(.inserted)
        
        // Provide haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func insertFinalResult() {
        if let session = SharedDictationManager.shared.getSession(), 
           !session.finalText.isEmpty,
           session.state == .ready {
            textDocumentProxy.insertText(session.finalText)
            SharedDictationManager.shared.updateState(.inserted)
        }
    }

    override func textWillChange(_ textInput: UITextInput?) {
    }

    override func textDidChange(_ textInput: UITextInput?) {
    }
}

// MARK: - Shared Dictation Manager

enum DictationState: String, Codable {
    case idle
    case launching
    case warming
    case recording
    case transcribing
    case ready
    case inserted
    case cancelled
    case failed
    case timeout
    
    // Commands from keyboard to background app
    case requestStart
    case requestStop
}

struct DictationSession: Codable {
    let sessionId: String
    let createdAt: Date
    var updatedAt: Date
    var state: DictationState
    var partialText: String = ""
    var finalText: String = ""
    var revision: Int = 0
    var error: String?
}

class SharedDictationManager {
    static let shared = SharedDictationManager()
    private let appGroupIdentifier = "group.NaichengDeng.testvoice"
    private let sessionKey = "dictation.session"
    
    private var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
    
    func saveSession(_ session: DictationSession) {
        if let data = try? JSONEncoder().encode(session) {
            defaults?.set(data, forKey: sessionKey)
            defaults?.synchronize()
        }
    }
    
    func getSession() -> DictationSession? {
        guard let data = defaults?.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(DictationSession.self, from: data)
    }
    
    func updateState(_ state: DictationState, error: String? = nil) {
        var session = getSession() ?? DictationSession(sessionId: UUID().uuidString, createdAt: Date(), updatedAt: Date(), state: .idle)
        session.state = state
        session.updatedAt = Date()
        session.error = error
        saveSession(session)
    }
    
    func updateText(partial: String, final: String) {
        guard var session = getSession() else { return }
        session.partialText = partial
        session.finalText = final
        session.revision += 1
        session.updatedAt = Date()
        saveSession(session)
    }
    
    func clearSession() {
        defaults?.removeObject(forKey: sessionKey)
        defaults?.synchronize()
    }
}
