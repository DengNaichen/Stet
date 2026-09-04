//
//  KeyboardViewController.swift
//  StetKeyboard
//
//  Created by Naicheng Deng on 2026-04-30.
//

import SwiftUI
import UIKit

private enum KeyboardButtonState: Equatable {
    case idle
    case pending
    case recording
    case processing
}

final class KeyboardViewController: UIInputViewController {
    private enum Layout {
        static let actionDiameter: CGFloat = 112
        static let returnWidth: CGFloat = 120
        static let returnHeight: CGFloat = 52
        static let utilityDiameter: CGFloat = 52
        static let horizontalInset: CGFloat = 20
        static let actionSpacing: CGFloat = 20
        static let actionStackVerticalOffset: CGFloat = 4
    }

    private let deleteButton = UIButton(type: .system)
    private let actionButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)
    private let actionStack = UIStackView()
    private var listeningShaderHost: UIHostingController<DictationLevelShaderView>?

    private var buttonState: KeyboardButtonState = .idle
    private var pollTimer: Timer?
    private var deleteInitialTimer: Timer?
    private var deleteRepeatTimer: Timer?
    private var shaderSampleTimer: DispatchSourceTimer?
    private var latestVolume: Double = 0
    private var selectedTheme = MobileDictationVisualTheme.storedMobileTheme
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
        selectedTheme = MobileDictationVisualTheme.storedMobileTheme
        updateActionButton()
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
        stopDeleteRepeat()
        updateListeningShader(level: latestVolume, isPaused: true)
        stopListeningShaderUpdates()

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
        actionButton.accessibilityIdentifier = "DictationButton"
        actionButton.layer.cornerRadius = Layout.actionDiameter / 2
        actionButton.layer.shadowColor = UIColor.black.cgColor
        actionButton.layer.shadowOpacity = 0.22
        actionButton.layer.shadowRadius = 12
        actionButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        actionButton.layer.masksToBounds = false

        NSLayoutConstraint.activate([
            actionButton.widthAnchor.constraint(equalToConstant: Layout.actionDiameter),
            actionButton.heightAnchor.constraint(equalToConstant: Layout.actionDiameter),
        ])
    }

    private func configureControlButtons() {
        configureEditingButton(
            deleteButton,
            systemImage: "delete.left.fill",
            accessibilityLabel: "Delete",
            width: Layout.utilityDiameter,
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
            deleteButton.topAnchor.constraint(equalTo: actionButton.topAnchor),
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
        height: CGFloat = 52,
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
                pointSize: 20,
                weight: .regular
            )
        }

        if title != nil {
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updatedAttributes = attributes
                updatedAttributes.font = .preferredFont(forTextStyle: .body)
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
            pointSize: 28,
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
            nextKeyboardButton.widthAnchor.constraint(equalToConstant: 52),
            nextKeyboardButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func updateActionButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.contentInsets = .zero
        actionButton.isUserInteractionEnabled = true

        switch buttonState {
        case .idle:
            configuration.image = UIImage(systemName: "mic.fill")
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: 30,
                weight: .medium
            )
            actionButton.isEnabled = true
            actionButton.accessibilityLabel = "Start Dictation"
            actionButton.accessibilityValue = nil

        case .pending:
            configuration.showsActivityIndicator = true
            actionButton.isEnabled = true
            actionButton.accessibilityLabel = "Cancel Dictation"
            actionButton.accessibilityValue = "Starting"

        case .recording:
            actionButton.isEnabled = true
            actionButton.accessibilityLabel = "Stop Dictation"
            actionButton.accessibilityValue = "Recording"

        case .processing:
            actionButton.isEnabled = true
            actionButton.isUserInteractionEnabled = false
            actionButton.accessibilityLabel = "Processing Dictation"
            actionButton.accessibilityValue = nil
        }

        actionButton.configuration = configuration
        switch buttonState {
        case .recording:
            ensureListeningShaderHost()
            updateListeningShader(level: latestVolume, isPaused: false)
            startListeningShaderUpdates()
        case .processing:
            ensureListeningShaderHost()
            updateListeningShader(level: latestVolume, isPaused: true)
            stopListeningShaderUpdates()
        case .idle, .pending:
            stopListeningShaderUpdates()
            removeListeningShaderHost()
        }
    }

    @objc private func handleActionButton() {
        switch buttonState {
        case .idle:
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

    private func startListeningShaderUpdates() {
        guard shaderSampleTimer == nil else { return }

        latestVolume = Double(SharedDictationManager.shared.readVolume())
        updateListeningShader(level: latestVolume, isPaused: false)

        let sampleTimer = DispatchSource.makeTimerSource(
            flags: [],
            queue: DispatchQueue(label: "com.stet.keyboard.shader", qos: .userInitiated)
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
                self.updateListeningShader(level: level, isPaused: false)
            }
        }
        shaderSampleTimer = sampleTimer
        sampleTimer.activate()
    }

    private func stopListeningShaderUpdates() {
        shaderSampleTimer?.setEventHandler {}
        shaderSampleTimer?.cancel()
        shaderSampleTimer = nil
    }

    private func ensureListeningShaderHost() {
        guard listeningShaderHost == nil else {
            if let shaderView = listeningShaderHost?.view {
                actionButton.bringSubviewToFront(shaderView)
            }
            return
        }

        let host = UIHostingController(
            rootView: makeListeningShader(level: latestVolume, isPaused: false)
        )
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        host.view.isUserInteractionEnabled = false
        host.view.accessibilityElementsHidden = true
        actionButton.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: actionButton.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: actionButton.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: actionButton.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: actionButton.bottomAnchor),
        ])
        host.didMove(toParent: self)
        listeningShaderHost = host
    }

    private func updateListeningShader(level: Double, isPaused: Bool) {
        listeningShaderHost?.rootView = makeListeningShader(level: level, isPaused: isPaused)
    }

    private func removeListeningShaderHost() {
        guard let host = listeningShaderHost else {
            latestVolume = 0
            return
        }
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        listeningShaderHost = nil
        latestVolume = 0
    }

    private func makeListeningShader(level: Double, isPaused: Bool) -> DictationLevelShaderView {
        DictationLevelShaderView(
            level: level,
            diameter: Layout.actionDiameter,
            preferredFramesPerSecond: 40,
            isPaused: isPaused,
            theme: selectedTheme
        )
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
                startListeningShaderUpdates()
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
