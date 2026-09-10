#if os(macOS)
    import Foundation

    extension MacAppSessionController {
        var isDictationBlockingMeeting: Bool {
            switch dictationState {
            case .starting, .listening, .processing:
                return true
            case .idle, .result, .clipboardPending, .error:
                return false
            }
        }

        func handleMeetingHotkeyPressed() {
            guard !isDictationBlockingMeeting else { return }

            if requiresOnboarding && !onboardingStepState.allowsAudioCapture {
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            guard hasRequiredPermissions else {
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            onMeetingHotkey()
        }
    }
#endif
