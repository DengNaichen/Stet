#if os(macOS)
    import Foundation
    import StetVisuals

    extension MacAppSessionController {
        func chooseOnboardingMode(_ mode: MacOnboardingMode) {
            guard requiresOnboarding else {
                onboardingModeState = mode
                onboardingStepState = .done
                notifyChange()
                return
            }

            onboardingModeState = mode
            onboardingStepState = .apiKey
            notifyChange()
        }

        func selectOnboardingAppearanceTheme(_ theme: MacDictationVisualTheme) {
            onboardingAppearanceThemeState = theme
            hasAppliedOnboardingAppearanceTheme = false
            notifyChange()
        }

        func applyOnboardingAppearanceTheme() {
            defaults.set(onboardingAppearanceThemeState.rawValue, forKey: MacPreferences.shaderTheme)
            hasAppliedOnboardingAppearanceTheme = true
            notifyChange()
        }

        func advanceOnboarding() {
            guard requiresOnboarding else {
                onboardingStepState = .done
                notifyChange()
                return
            }

            switch onboardingStepState {
            case .download:
                onboardingStepState = .apiKey
            case .permissions:
                guard hasRequiredPermissions else { return }
                onboardingStepState = .shortcut
            case .shortcut:
                prepareFirstSuccessStep()
                onboardingStepState = .firstSuccess
            case .firstSuccess:
                guard canContinueFirstSuccessOnboarding || canSkipFirstSuccessOnboarding else { return }
                onboardingStepState = .appearance
            case .apiKey, .appearance, .done:
                break
            }

            notifyChange()
        }

        func retreatOnboarding() {
            guard requiresOnboarding else {
                onboardingStepState = .done
                notifyChange()
                return
            }

            switch onboardingStepState {
            case .download:
                break
            case .apiKey:
                onboardingStepState = .download
            case .permissions:
                onboardingStepState = .apiKey
            case .shortcut:
                onboardingStepState = .permissions
            case .firstSuccess:
                onboardingStepState = .shortcut
            case .appearance:
                onboardingStepState = .firstSuccess
            case .done:
                onboardingStepState = .appearance
            }

            notifyChange()
        }

        func completeCredentialOnboarding(mode: MacOnboardingMode) {
            onboardingModeState = mode
            guard requiresOnboarding else {
                onboardingStepState = .done
                notifyChange()
                return
            }

            onboardingStepState = .permissions
            notifyChange()
        }

        func finishOnboarding() {
            defaults.set(true, forKey: MacPreferences.onboardingCompleted)
            onboardingStepState = .done
            onboardingModeState = nil
            permissionGateController.hide()
            notifyChange()
        }

        func setDebugForceOnboardingEnabled(_ enabled: Bool) {
            defaults.set(enabled, forKey: MacPreferences.debugForceOnboarding)

            #if DEBUG
                if !enabled {
                    defaults.set(true, forKey: MacPreferences.onboardingCompleted)
                }
            #endif

            resetOnboardingProgressIfNeeded()
            notifyChange()
        }

        func resetOnboardingForDebug() {
            defaults.set(false, forKey: MacPreferences.onboardingCompleted)
            onboardingModeState = nil
            resetOnboardingProgressIfNeeded(forceRestart: true)
            notifyChange()
        }
    }

    extension MacAppSessionController {
        func updateOnboardingProgress(previousState: DictationState, state: DictationState) {
            if onboardingStepState == .firstSuccess {
                if case .result(let text) = state {
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    firstSuccessPreviewTextState = trimmedText.isEmpty ? nil : trimmedText
                    firstSuccessFailureMessageState = nil
                } else if case .clipboardPending(let text) = state {
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    firstSuccessPreviewTextState = trimmedText.isEmpty ? nil : trimmedText
                    firstSuccessFailureMessageState = nil
                } else if case .error(let failure) = state {
                    firstSuccessFailureCount += 1
                    firstSuccessFailureMessageState = inferredFirstSuccessFailureMessage(for: failure)
                }
            }

            notifyChange()
        }

        func resetShortcutOnboardingState() {
            shortcutTestDetectedPressState = false
            shortcutTestCompletedRoundTripState = false
            shortcutTestPreviewTextState = nil
        }

        func prepareFirstSuccessStep() {
            firstSuccessPreviewTextState = nil
            firstSuccessFailureMessageState = nil
            firstSuccessFailureCount = 0

            switch dictationState {
            case .result, .error, .clipboardPending:
                workflowController.dictationViewModel.send(.resetTapped)
            case .idle, .starting, .listening, .processing:
                break
            }
        }

        func inferredFirstSuccessFailureMessage(for failure: DictationFailure) -> String {
            if failure == .autoPastePermissionMissing {
                return "Unable to paste automatically, please grant Input Monitoring or Accessibility access."
            }

            switch failure.classification {
            case .authentication:
                return "Connection unavailable, please re-verify your login status."
            case .configuration:
                if onboardingModeState == .apiKey {
                    return "Connection unavailable, please re-verify your API Key."
                }
                return "Model configuration unavailable, please check provider settings."
            case .network:
                return "Processing failed, please check your network or model configuration."
            case .permissions:
                return "Unable to access microphone, please check system permissions."
            case .noSpeech:
                return "No voice input detected, please try again."
            case .output:
                return "Text output failed, but your transcription is available."
            case .service, .state, .unknown:
                return "Dictation failed, please try again."
            }
        }

        func resetOnboardingProgressIfNeeded(forceRestart: Bool = false) {
            guard requiresOnboarding else {
                onboardingStepState = .done
                if !isDebugForceOnboardingEnabled {
                    onboardingModeState = nil
                }
                return
            }

            guard forceRestart || onboardingStepState == .done else {
                return
            }

            onboardingStepState = .download
        }
    }
#endif
