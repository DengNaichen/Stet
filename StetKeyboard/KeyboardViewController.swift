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
    private let controlRow = UIStackView()
    private let deleteButton = UIButton(type: .system)
    private let actionButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)
    private let waveformView = KeyboardWaveformView()

    private var buttonState: KeyboardButtonState = .idle
    private var pollTimer: Timer?
    private var waveformDisplayLink: CADisplayLink?
    private var waveformSampleTimer: DispatchSourceTimer?
    private var latestVolume: Float = 0
    private var lastProcessedSessionId: String?
    private var pendingSessionId: String?
    private var isWakingMainApp = false

    private lazy var waveformDisplayLinkTarget = DisplayLinkTarget { [weak self] in
        self?.drawLatestVolume()
    }

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()

    override func loadView() {
        view = UIInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureActionButton()
        configureControlRow()
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
        // The origin stored in the transactional session file also repairs the
        // pending UserDefaults hint if a previous extension process exited between
        // the two writes.
        let manager = SharedDictationManager.shared
        if let savedSessionId = manager.getPendingKeyboardSessionId() {
            pendingSessionId = savedSessionId
        } else if let session = manager.getSession(),
            session.origin == .keyboard,
            isActiveState(session.state)
        {
            pendingSessionId = session.sessionId
            manager.savePendingKeyboardSessionId(session.sessionId)
        } else {
            pendingSessionId = nil
        }
        startPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPolling()
        stopWaveformUpdates()

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

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.tintColor = .systemBackground
        waveformView.isHidden = true
        actionButton.addSubview(waveformView)

        NSLayoutConstraint.activate([
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            actionButton.heightAnchor.constraint(equalToConstant: 52),
            waveformView.centerXAnchor.constraint(equalTo: actionButton.centerXAnchor),
            waveformView.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),
            waveformView.widthAnchor.constraint(equalToConstant: 92),
            waveformView.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func configureControlRow() {
        configureEditingButton(
            deleteButton,
            systemImage: "delete.left.fill",
            accessibilityLabel: "Delete",
            action: #selector(handleDeleteButton)
        )
        configureEditingButton(
            returnButton,
            systemImage: "return",
            accessibilityLabel: "New Line",
            action: #selector(handleReturnButton)
        )

        controlRow.axis = .horizontal
        controlRow.alignment = .center
        controlRow.spacing = 10
        controlRow.translatesAutoresizingMaskIntoConstraints = false
        controlRow.addArrangedSubview(deleteButton)
        controlRow.addArrangedSubview(actionButton)
        controlRow.addArrangedSubview(returnButton)
        view.addSubview(controlRow)

        NSLayoutConstraint.activate([
            controlRow.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            controlRow.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            controlRow.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 8
            ),
            controlRow.trailingAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -8
            ),
        ])
    }

    private func configureEditingButton(
        _ button: UIButton,
        systemImage: String,
        accessibilityLabel: String,
        action: Selector
    ) {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .medium
        configuration.image = UIImage(systemName: systemImage)
        configuration.baseBackgroundColor = .secondarySystemFill
        configuration.baseForegroundColor = .label

        button.configuration = configuration
        button.accessibilityLabel = accessibilityLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 52),
            button.heightAnchor.constraint(equalToConstant: 52),
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
            actionButton.accessibilityLabel = "Start Dictation"
            actionButton.accessibilityValue = nil

        case .pending:
            configuration.title = "Starting…"
            configuration.showsActivityIndicator = true
            actionButton.isEnabled = false
            actionButton.accessibilityLabel = "Starting Dictation"
            actionButton.accessibilityValue = nil

        case .recording:
            actionButton.isEnabled = true
            actionButton.accessibilityLabel = "Stop Dictation"
            actionButton.accessibilityValue = "Recording"

        case .processing:
            configuration.title = "Processing…"
            configuration.showsActivityIndicator = true
            actionButton.isEnabled = false
            actionButton.accessibilityLabel = "Processing Dictation"
            actionButton.accessibilityValue = nil
        }

        actionButton.configuration = configuration
        let showsWaveform = buttonState == .recording
        waveformView.isHidden = !showsWaveform
        actionButton.bringSubviewToFront(waveformView)

        if showsWaveform {
            startWaveformUpdates()
        } else {
            stopWaveformUpdates()
        }
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

    @objc private func handleDeleteButton() {
        textDocumentProxy.deleteBackward()
    }

    @objc private func handleReturnButton() {
        textDocumentProxy.insertText("\n")
    }

    private func handleMicDown() {
        let sessionId = UUID().uuidString
        guard SharedDictationManager.shared.beginKeyboardSession(sessionId: sessionId) else {
            pendingSessionId = nil
            publishState(.idle)
            return
        }

        pendingSessionId = sessionId
        SharedDictationManager.shared.updateVolume(0)

        // A live main app will observe the shared request; otherwise wake it explicitly.
        if !SharedDictationManager.shared.mainAppAlive(within: 0.6) {
            isWakingMainApp = openMainApp(sessionId: sessionId)
        }

        publishState(.pending)
    }

    private func handleMicUp() {
        guard let sessionId = pendingSessionId else { return }
        let manager = SharedDictationManager.shared
        let didRequestStop = manager.transitionState(
            for: sessionId,
            from: [.requestStart, .launching, .warming, .recording],
            to: .requestStop
        )
        if !didRequestStop {
            guard let session = manager.getSession(),
                session.sessionId == sessionId,
                [.requestStop, .transcribing, .ready].contains(session.state)
            else {
                cleanupSession(sessionId: sessionId)
                publishState(.idle)
                return
            }
        }

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

    private func startWaveformUpdates() {
        guard waveformDisplayLink == nil else { return }

        latestVolume = 0
        waveformView.reset()

        let sampleTimer = DispatchSource.makeTimerSource(
            flags: [],
            queue: DispatchQueue(label: "com.stet.keyboard.waveform", qos: .userInitiated)
        )
        sampleTimer.schedule(
            deadline: .now(),
            repeating: .milliseconds(33),
            leeway: .milliseconds(8)
        )
        sampleTimer.setEventHandler { [weak self] in
            let level = SharedDictationManager.shared.readVolume()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.buttonState == .recording else { return }
                self.latestVolume = level
            }
        }
        waveformSampleTimer = sampleTimer
        sampleTimer.activate()

        let displayLink = CADisplayLink(
            target: waveformDisplayLinkTarget,
            selector: #selector(DisplayLinkTarget.tick(_:))
        )
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 15,
            maximum: 30,
            preferred: 30
        )
        displayLink.add(to: .main, forMode: .common)
        waveformDisplayLink = displayLink
    }

    private func stopWaveformUpdates() {
        waveformDisplayLink?.invalidate()
        waveformDisplayLink = nil

        waveformSampleTimer?.setEventHandler {}
        waveformSampleTimer?.cancel()
        waveformSampleTimer = nil

        latestVolume = 0
        waveformView.reset()
    }

    private func drawLatestVolume() {
        guard buttonState == .recording else { return }
        waveformView.update(level: latestVolume)
    }

    private func tick() {
        guard let pendingSessionId else {
            publishState(.idle)
            return
        }

        guard let session = SharedDictationManager.shared.getSession(),
            session.sessionId == pendingSessionId,
            session.origin != .app
        else {
            cleanupSession(sessionId: pendingSessionId)
            publishState(.idle)
            return
        }

        switch session.state {
        case .idle:
            cleanupSession(sessionId: session.sessionId)
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
            cleanupSession(sessionId: session.sessionId)
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
        guard buttonState != state else {
            if state == .recording {
                startWaveformUpdates()
            }
            return
        }
        buttonState = state
        updateActionButton()
    }

    private func insertTranscription(_ session: DictationSession) {
        guard pendingSessionId == session.sessionId else { return }
        guard
            SharedDictationManager.shared.transitionState(
                for: session.sessionId,
                from: [.ready],
                to: .inserted
            )
        else { return }

        if !session.finalText.isEmpty {
            textDocumentProxy.insertText(session.finalText)
            notificationFeedback.notificationOccurred(.success)
        }
        lastProcessedSessionId = session.sessionId
        cleanupSession(sessionId: session.sessionId)
    }

    private func cancelOurSession() {
        guard let sessionId = pendingSessionId else { return }
        _ = SharedDictationManager.shared.transitionState(
            for: sessionId,
            from: [.requestStart, .launching, .warming, .recording, .requestStop, .transcribing],
            to: .cancelled
        )
        cleanupSession(sessionId: sessionId)
    }

    private func cleanupSession(sessionId: String) {
        if pendingSessionId == sessionId {
            pendingSessionId = nil
        }
        SharedDictationManager.shared.updateVolume(0)
        SharedDictationManager.shared.clearPendingKeyboardSessionId(ifMatching: sessionId)
    }
}

private final class DisplayLinkTarget {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func tick(_: CADisplayLink) {
        action()
    }
}
