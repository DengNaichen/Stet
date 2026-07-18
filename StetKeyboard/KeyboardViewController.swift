//
//  KeyboardViewController.swift
//  StetKeyboard
//
//  Created by Naicheng Deng on 2026-04-30.
//

import UIKit

private enum KeyboardButtonState: Equatable {
    case idle
    case pending
    case recording
    case processing
}

final class KeyboardViewController: UIInputViewController {
    private let actionButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)

    private var buttonState: KeyboardButtonState = .idle
    private var pollTimer: Timer?
    private var lastProcessedSessionId: String?
    private var pendingSessionId: String?
    private var isWakingMainApp = false

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()

    override func loadView() {
        view = UIInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureActionButton()
        configureNextKeyboardButton()
        updateActionButton()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        nextKeyboardButton.isHidden = !needsInputModeSwitchKey
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isWakingMainApp = false
        impactFeedback.prepare()
        notificationFeedback.prepare()

        // The extension may be recreated while the main app is handling a request.
        pendingSessionId = SharedDictationManager.shared.getPendingKeyboardSessionId()
        startPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPolling()

        // Keep the request alive only when this extension is intentionally waking Stet.
        if !isWakingMainApp,
            let session = SharedDictationManager.shared.getSession(),
            session.sessionId == pendingSessionId
        {
            switch session.state {
            case .requestStart, .launching, .warming, .recording:
                cancelOurSession()
            default:
                break
            }
        }
    }

    private func configureActionButton() {
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(handleActionButton), for: .touchUpInside)
        view.addSubview(actionButton)

        NSLayoutConstraint.activate([
            actionButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            actionButton.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            actionButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func configureNextKeyboardButton() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "globe")
        configuration.baseForegroundColor = .label

        nextKeyboardButton.configuration = configuration
        nextKeyboardButton.accessibilityLabel = "Next Keyboard"
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        nextKeyboardButton.addTarget(
            self,
            action: #selector(handleNextKeyboard(_:event:)),
            for: .allTouchEvents
        )
        view.addSubview(nextKeyboardButton)

        NSLayoutConstraint.activate([
            nextKeyboardButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            nextKeyboardButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            nextKeyboardButton.widthAnchor.constraint(equalToConstant: 44),
            nextKeyboardButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func updateActionButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.imagePadding = 8
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground

        switch buttonState {
        case .idle:
            configuration.title = "Tap to speak"
            configuration.image = UIImage(systemName: "mic.fill")
            actionButton.isEnabled = true

        case .pending:
            configuration.title = "Starting…"
            configuration.showsActivityIndicator = true
            actionButton.isEnabled = false

        case .recording:
            configuration.title = "Tap to stop"
            configuration.image = UIImage(systemName: "stop.fill")
            actionButton.isEnabled = true

        case .processing:
            configuration.title = "Processing…"
            configuration.showsActivityIndicator = true
            actionButton.isEnabled = false
        }

        actionButton.configuration = configuration
    }

    @objc private func handleActionButton() {
        switch buttonState {
        case .idle:
            handleMicDown()
        case .recording:
            handleMicUp()
        case .pending, .processing:
            return
        }

        impactFeedback.impactOccurred()
        impactFeedback.prepare()
    }

    @objc private func handleNextKeyboard(_ sender: UIButton, event: UIEvent) {
        handleInputModeList(from: sender, with: event)
    }

    private func handleMicDown() {
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

        // A live main app will observe the shared request; otherwise wake it explicitly.
        if !SharedDictationManager.shared.mainAppAlive(within: 0.6) {
            isWakingMainApp = openMainApp(sessionId: sessionId)
        }

        publishState(.pending)
    }

    private func handleMicUp() {
        guard let sessionId = pendingSessionId else { return }
        let currentSession = SharedDictationManager.shared.getSession()
        guard currentSession == nil || currentSession?.sessionId == sessionId else {
            cleanupSession()
            publishState(.idle)
            return
        }

        var session =
            currentSession
            ?? DictationSession(
                sessionId: sessionId,
                createdAt: Date(),
                updatedAt: Date(),
                state: .requestStop
            )
        session.state = .requestStop
        session.updatedAt = Date()
        SharedDictationManager.shared.saveSession(session)

        publishState(.processing)
    }

    private func openMainApp(sessionId: String) -> Bool {
        let urlString = "stetmobile://dictate?session_id=\(sessionId)"
        guard let url = URL(string: urlString) else { return false }

        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:]) { [weak self] didOpen in
                    if !didOpen {
                        self?.isWakingMainApp = false
                    }
                }
                return true
            }
            responder = current.next
        }
        return false
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        tick()
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
            let appDead = !SharedDictationManager.shared.mainAppAlive(within: 2.0)
            let stale = Date().timeIntervalSince(session.updatedAt) > 10.0
            if appDead && stale {
                cancelOurSession()
                publishState(.idle)
            } else {
                publishState(.pending)
            }

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

    private func isActiveState(_ state: DictationState) -> Bool {
        switch state {
        case .requestStart, .launching, .warming, .recording, .requestStop, .transcribing, .ready:
            return true
        default:
            return false
        }
    }

    private func publishState(_ state: KeyboardButtonState) {
        guard buttonState != state else { return }
        buttonState = state
        updateActionButton()
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
