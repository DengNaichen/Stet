#if os(macOS)
    import KeyboardShortcuts

    @MainActor
    struct KeyboardShortcutsHotkeyRegistrar: MacDictationHotkeyRegistering {
        func clearDictationHandlers() {
            KeyboardShortcuts.removeHandler(for: .dictationHotkey)
        }

        func registerDictationKeyDown(_ handler: @escaping () -> Void) {
            KeyboardShortcuts.onKeyDown(for: .dictationHotkey) {
                Task { @MainActor in
                    handler()
                }
            }
        }

        func registerDictationKeyUp(_ handler: @escaping () -> Void) {
            KeyboardShortcuts.onKeyUp(for: .dictationHotkey) {
                Task { @MainActor in
                    handler()
                }
            }
        }

        func clearMeetingHandlers() {
            KeyboardShortcuts.removeHandler(for: .meetingRecordingHotkey)
        }

        func registerMeetingKeyDown(_ handler: @escaping () -> Void) {
            KeyboardShortcuts.onKeyDown(for: .meetingRecordingHotkey) {
                Task { @MainActor in
                    handler()
                }
            }
        }
    }
#endif
