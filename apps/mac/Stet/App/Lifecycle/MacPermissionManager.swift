#if os(macOS)
import AppKit
import AVFoundation

@MainActor
final class MacPermissionManager {
    enum PermissionStatus {
        case allowed
        case notRequested
        case needsAccess
        case unavailable

        var text: String {
            switch self {
            case .allowed:
                return "Allowed"
            case .notRequested:
                return "Not Requested"
            case .needsAccess:
                return "Needs Access"
            case .unavailable:
                return "Unknown"
            }
        }

        var needsAttention: Bool {
            switch self {
            case .allowed:
                return false
            case .notRequested, .needsAccess, .unavailable:
                return true
            }
        }

        var isAllowed: Bool {
            switch self {
            case .allowed:
                return true
            case .notRequested, .needsAccess, .unavailable:
                return false
            }
        }

        var canRequestInApp: Bool {
            switch self {
            case .notRequested:
                return true
            case .needsAccess, .unavailable, .allowed:
                return false
            }
        }
    }

    private let textInjectionService: any TextInjectionService

    init(textInjectionService: any TextInjectionService) {
        self.textInjectionService = textInjectionService
    }

    var hasRequiredPermissions: Bool {
        microphoneAccessStatus.isAllowed && textInjectionService.accessState.canSimulateInput
    }

    var microphoneAccessStatus: PermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .allowed
        case .undetermined:
            return .notRequested
        case .denied:
            return .needsAccess
        @unknown default:
            return .unavailable
        }
    }

    var microphoneAccessNeedsAttention: Bool {
        microphoneAccessStatus.needsAttention
    }

    var microphoneAccessStatusText: String {
        microphoneAccessStatus.text
    }

    var microphonePermissionActionTitle: String {
        microphoneAccessStatus.canRequestInApp ? "Request Access" : "Open Settings"
    }

    var autoPasteAccessNeedsAttention: Bool {
        !textInjectionService.accessState.canSimulateInput
    }

    var autoPasteStatusText: String {
        let state = textInjectionService.accessState

        switch (state.hasAccessibilityAccess, state.hasPostEventAccess) {
        case (true, true):
            return "Enabled"
        case (true, false):
            return "Accessibility Only"
        case (false, true):
            return "Input Injection Only"
        case (false, false):
            return "Needs Access"
        }
    }

    var speechRecognitionStatusText: String {
        "Not Required"
    }

    func requestAutoPasteAccess() {
        textInjectionService.requestAccess()
    }

    func openAccessibilitySettings() {
        textInjectionService.openAccessibilitySettings()
    }
    
    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
#endif
