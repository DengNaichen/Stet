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
    case done
}

final class KeyboardViewController: UIInputViewController {
    private enum Layout {
        static let keyboardHeight: CGFloat = 236
        static let actionDiameter: CGFloat = 124
        static let returnWidth: CGFloat = 120
        static let returnHeight: CGFloat = 48
        static let utilityDiameter: CGFloat = 48
        static let horizontalInset: CGFloat = 20
        static let actionSpacing: CGFloat = 14
        static let actionStackVerticalOffset: CGFloat = 2
    }

    private let deleteButton = UIButton(type: .system)
    private let actionButton = UIButton(type: .custom)
    private let returnButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)
    private let actionStack = UIStackView()
    private let thinkingOrbView = KeyboardThinkingOrbCanvasView()

    private var buttonState: KeyboardButtonState = .idle
    private var isVisible = false
    private var pollTimer: Timer?
    private var doneResetTimer: Timer?
    private var deleteInitialTimer: Timer?
    private var deleteRepeatTimer: Timer?
    private var volumeSampleTimer: DispatchSourceTimer?
    private var latestVolume: Double = 0
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
        configureKeyboardHeight()
        configureActionButton()
        configureControlButtons()
        configureNextKeyboardButton()
        updateActionButton()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        nextKeyboardButton.isHidden = !needsInputModeSwitchKey
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        updateActionButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
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
            if buttonState == .processing || buttonState == .pending || buttonState == .recording {
                buttonState = .idle
            }
        }
        startPolling()
        updateActionButton()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        stopPolling()
        stopDoneResetTimer()
        stopDeleteRepeat()
        stopVolumeUpdates()
        updateThinkingOrb()

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

    private func configureKeyboardHeight() {
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: Layout.keyboardHeight)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true
    }

    private func configureActionButton() {
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(handleActionButton), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(handleActionPressDown), for: .touchDown)
        actionButton.addTarget(
            self,
            action: #selector(handleActionPressUp),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )
        actionButton.accessibilityIdentifier = "DictationButton"
        // Non-zero alpha ensures UIKit hit-testing always hits the full circular target.
        actionButton.backgroundColor = UIColor.label.withAlphaComponent(0.001)
        actionButton.layer.cornerRadius = Layout.actionDiameter / 2
        actionButton.clipsToBounds = false

        thinkingOrbView.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addSubview(thinkingOrbView)

        NSLayoutConstraint.activate([
            actionButton.widthAnchor.constraint(equalToConstant: Layout.actionDiameter),
            actionButton.heightAnchor.constraint(equalToConstant: Layout.actionDiameter),
            thinkingOrbView.leadingAnchor.constraint(equalTo: actionButton.leadingAnchor),
            thinkingOrbView.trailingAnchor.constraint(equalTo: actionButton.trailingAnchor),
            thinkingOrbView.topAnchor.constraint(equalTo: actionButton.topAnchor),
            thinkingOrbView.bottomAnchor.constraint(equalTo: actionButton.bottomAnchor),
        ])
    }

    private func configureControlButtons() {
        configureEditingButton(
            deleteButton,
            systemImage: "delete.left.fill",
            accessibilityLabel: "Delete",
            width: Layout.utilityDiameter,
            height: Layout.utilityDiameter,
            action: nil
        )
        deleteButton.accessibilityIdentifier = "DeleteButton"
        deleteButton.addTarget(self, action: #selector(handleDeleteDown), for: .touchDown)
        deleteButton.addTarget(
            self,
            action: #selector(handleDeleteUp),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )

        configureEditingButton(
            returnButton,
            title: "return",
            accessibilityLabel: "New Line",
            width: Layout.returnWidth,
            height: Layout.returnHeight,
            action: #selector(handleReturnButton)
        )
        returnButton.accessibilityIdentifier = "ReturnButton"

        actionStack.axis = .vertical
        actionStack.alignment = .center
        actionStack.spacing = Layout.actionSpacing
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.addArrangedSubview(actionButton)
        actionStack.addArrangedSubview(returnButton)
        view.addSubview(actionStack)
        view.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            actionStack.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            actionStack.centerYAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.centerYAnchor,
                constant: Layout.actionStackVerticalOffset
            ),
            deleteButton.topAnchor.constraint(equalTo: actionButton.topAnchor, constant: 8),
            deleteButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.horizontalInset
            ),
        ])
    }

    private func configureEditingButton(
        _ button: UIButton,
        systemImage: String? = nil,
        title: String? = nil,
        accessibilityLabel: String,
        width: CGFloat,
        height: CGFloat = 48,
        action: Selector?
    ) {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.image = systemImage.flatMap(UIImage.init(systemName:))
        configuration.title = title
        configuration.baseBackgroundColor = .secondarySystemFill
        configuration.baseForegroundColor = .label

        if systemImage != nil {
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: 19,
                weight: .regular
            )
        }

        if title != nil {
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updatedAttributes = attributes
                updatedAttributes.font = .preferredFont(forTextStyle: .callout)
                return updatedAttributes
            }
        }

        button.configuration = configuration
        button.accessibilityLabel = accessibilityLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        if let action {
            button.addTarget(self, action: action, for: .touchUpInside)
        }

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: width),
            button.heightAnchor.constraint(equalToConstant: height),
        ])
    }

    private func configureNextKeyboardButton() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "globe")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 26,
            weight: .regular
        )
        configuration.baseForegroundColor = .label

        nextKeyboardButton.configuration = configuration
        nextKeyboardButton.accessibilityLabel = "Next Keyboard"
        nextKeyboardButton.accessibilityIdentifier = "NextKeyboardButton"
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        nextKeyboardButton.addTarget(
            self,
            action: #selector(handleNextKeyboard(_:event:)),
            for: .allTouchEvents
        )
        view.addSubview(nextKeyboardButton)

        NSLayoutConstraint.activate([
            nextKeyboardButton.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: Layout.horizontalInset
            ),
            nextKeyboardButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            nextKeyboardButton.widthAnchor.constraint(equalToConstant: 48),
            nextKeyboardButton.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func updateActionButton() {
        actionButton.isEnabled = true
        actionButton.isUserInteractionEnabled = buttonState != .processing

        switch buttonState {
        case .idle:
            actionButton.accessibilityLabel = "Start Dictation"
            actionButton.accessibilityValue = nil
            stopVolumeUpdates()
            latestVolume = 0

        case .pending:
            actionButton.accessibilityLabel = "Cancel Dictation"
            actionButton.accessibilityValue = "Starting"
            stopVolumeUpdates()
            latestVolume = 0

        case .recording:
            actionButton.accessibilityLabel = "Stop Dictation"
            actionButton.accessibilityValue = "Recording"
            startVolumeUpdates()

        case .processing:
            actionButton.accessibilityLabel = "Processing Dictation"
            actionButton.accessibilityValue = "Thinking"
            stopVolumeUpdates()

        case .done:
            actionButton.accessibilityLabel = "Dictation Complete"
            actionButton.accessibilityValue = "Done"
            stopVolumeUpdates()
            latestVolume = 0
        }

        updateThinkingOrb()
    }

    @objc private func handleActionPressDown() {
        guard buttonState != .processing else { return }
        UIView.animate(withDuration: 0.16, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0) {
            self.actionButton.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }
    }

    @objc private func handleActionPressUp() {
        UIView.animate(withDuration: 0.24, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.actionButton.transform = .identity
        }
    }

    @objc private func handleActionButton() {
        switch buttonState {
        case .idle, .done:
            stopDoneResetTimer()
            handleMicDown()
        case .pending:
            cancelOurSession()
            publishState(.idle)
        case .recording:
            handleMicUp()
        case .processing:
            return
        }

        impactFeedback.impactOccurred()
        impactFeedback.prepare()
    }

    @objc private func handleNextKeyboard(_ sender: UIButton, event: UIEvent) {
        handleInputModeList(from: sender, with: event)
    }

    @objc private func handleDeleteDown() {
        textDocumentProxy.deleteBackward()
        deleteInitialTimer?.invalidate()
        deleteInitialTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.beginDeleteRepeat()
        }
    }

    @objc private func handleDeleteUp() {
        stopDeleteRepeat()
    }

    private func beginDeleteRepeat() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            self?.textDocumentProxy.deleteBackward()
        }
    }

    private func stopDeleteRepeat() {
        deleteInitialTimer?.invalidate()
        deleteInitialTimer = nil
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
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

    private func startVolumeUpdates() {
        guard volumeSampleTimer == nil else { return }

        latestVolume = Double(SharedDictationManager.shared.readVolume())
        updateThinkingOrb()

        let sampleTimer = DispatchSource.makeTimerSource(
            flags: [],
            queue: DispatchQueue(label: "com.stet.keyboard.thinkingOrb", qos: .userInitiated)
        )
        sampleTimer.schedule(
            deadline: .now(),
            repeating: .milliseconds(60),
            leeway: .milliseconds(10)
        )
        sampleTimer.setEventHandler { [weak self] in
            let level = Double(SharedDictationManager.shared.readVolume())
            DispatchQueue.main.async { [weak self] in
                guard let self, self.buttonState == .recording else { return }
                self.latestVolume = level
                self.updateThinkingOrb()
            }
        }
        volumeSampleTimer = sampleTimer
        sampleTimer.activate()
    }

    private func stopVolumeUpdates() {
        volumeSampleTimer?.setEventHandler {}
        volumeSampleTimer?.cancel()
        volumeSampleTimer = nil
    }

    private func updateThinkingOrb() {
        let orbMode: KeyboardThinkingOrbMode
        let orbLevel: Double?
        switch buttonState {
        case .idle:
            orbMode = .idle
            orbLevel = nil
        case .pending:
            orbMode = .searching
            orbLevel = nil
        case .recording:
            orbMode = .listening
            orbLevel = latestVolume
        case .processing:
            orbMode = .thinking
            orbLevel = nil
        case .done:
            orbMode = .done
            orbLevel = nil
        }

        thinkingOrbView.configure(mode: orbMode, level: orbLevel, isActive: isVisible)
    }

    private func tick() {
        guard let pendingSessionId else {
            if buttonState != .done {
                publishState(.idle)
            }
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
            var insertedNonEmpty = false
            if session.sessionId != lastProcessedSessionId {
                insertedNonEmpty = insertTranscription(session)
            }
            if insertedNonEmpty {
                showDoneConfirmation()
            } else {
                publishState(.idle)
            }

        case .inserted, .cancelled, .failed, .timeout:
            cleanupSession(sessionId: session.sessionId)
            publishState(.idle)
        }
    }

    private func showDoneConfirmation() {
        stopDoneResetTimer()
        publishState(.done)
        doneResetTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            guard let self, self.buttonState == .done else { return }
            self.publishState(.idle)
        }
    }

    private func stopDoneResetTimer() {
        doneResetTimer?.invalidate()
        doneResetTimer = nil
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
                startVolumeUpdates()
            }
            return
        }
        buttonState = state
        updateActionButton()
    }

    @discardableResult
    private func insertTranscription(_ session: DictationSession) -> Bool {
        guard pendingSessionId == session.sessionId else { return false }
        guard
            SharedDictationManager.shared.transitionState(
                for: session.sessionId,
                from: [.ready],
                to: .inserted
            )
        else { return false }

        let insertedNonEmpty = !session.finalText.isEmpty
        if insertedNonEmpty {
            textDocumentProxy.insertText(session.finalText)
            notificationFeedback.notificationOccurred(.success)
        }
        lastProcessedSessionId = session.sessionId
        cleanupSession(sessionId: session.sessionId)
        return insertedNonEmpty
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
