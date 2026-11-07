#if os(macOS)
    import AppKit

    @MainActor
    enum MacMeetingSpeakerPreflight {
        static func prepare(_ settings: MeetingSpeakerSettings) async -> Bool? {
            guard settings.isEnabled else { return false }
            if await settings.isReadyForMeeting() { return true }
            let alert = NSAlert()
            alert.messageText = String(localized: "Speaker separation needs a model")
            alert.informativeText = String(
                localized:
                    "Download or repair the model, or record this meeting without separating speakers. Your saved preference will not change."
            )
            alert.addButton(withTitle: String(localized: "Download and Repair"))
            alert.addButton(withTitle: String(localized: "Record Without Speaker Separation"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            NSApp.activate(ignoringOtherApps: true)
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                settings.downloadAndEnable()
                return nil
            case .alertSecondButtonReturn:
                return false
            default:
                return nil
            }
        }
    }
#endif
