#if os(macOS)
    import KeyboardShortcuts

    @MainActor
    struct KeyboardShortcutsHotkeyRegistrar: MacDictationHotkeyRegistering {
        func clearDictationHandlers() {
            KeyboardShortcuts.removeHandler(for: .dictationHotkey)
        }

        func registerDictationKeyDown(_ handler: @escaping () -> Void) {
            KeyboardShortcuts.onKeyDown(for: .dictationHotkey) {
                MainActor.assumeIsolated {
                    handler()
                }
            }
        }

        func clearMeetingHandlers() {
            KeyboardShortcuts.removeHandler(for: .meetingRecordingHotkey)
        }

        func registerMeetingKeyDown(_ handler: @escaping () -> Void) {
            KeyboardShortcuts.onKeyDown(for: .meetingRecordingHotkey) {
                MainActor.assumeIsolated {
                    handler()
                }
            }
        }
    }
#endif
