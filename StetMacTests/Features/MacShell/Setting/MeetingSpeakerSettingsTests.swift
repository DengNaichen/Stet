#if os(macOS)
    import Foundation
    import Testing
    @testable import Stet

    @MainActor
    @Suite("Meeting speaker settings")
    struct MeetingSpeakerSettingsTests {
        @Test func firstEnableRequiresConsentAndOnlyEnablesAfterValidation() async throws {
            let root = TestSupport.temporaryDirectoryURL()
            defer { try? FileManager.default.removeItem(at: root) }
            let suite = UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = MeetingSpeakerModelStore(
                directory: root, files: [.init(path: "model", size: 1)],
                download: { _, destination, progress in
                    try Data([1]).write(to: destination)
                    progress(1)
                }, validate: { _ in })
            let settings = MeetingSpeakerSettings(store: store, defaults: defaults)
            #expect(!settings.isEnabled)
            settings.requestEnabled(true)
            #expect(settings.showsDownloadPrompt)
            #expect(!settings.isEnabled)
            #expect(!store.isComplete)
            settings.downloadAndEnable()
            #expect(await TestSupport.eventuallyAsync { await MainActor.run { settings.state == .ready } })
            #expect(settings.isEnabled)
            #expect(MeetingSpeakerSettings(store: store, defaults: defaults).isEnabled)
            settings.requestEnabled(false)
            #expect(!defaults.bool(forKey: MeetingSpeakerSettings.preferenceKey))
        }

        @Test func validationFailureDoesNotEnableAndMissingModelDoesNotClearPreference() async throws {
            let root = TestSupport.temporaryDirectoryURL()
            defer { try? FileManager.default.removeItem(at: root) }
            let suite = UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = MeetingSpeakerModelStore(
                directory: root, files: [.init(path: "model", size: 1)],
                download: { _, destination, _ in
                    try Data([1]).write(to: destination)
                }, validate: { _ in throw CocoaError(.fileReadCorruptFile) })
            let settings = MeetingSpeakerSettings(store: store, defaults: defaults)
            settings.downloadAndEnable()
            #expect(
                await TestSupport.eventuallyAsync {
                    await MainActor.run {
                        if case .failed = settings.state { return true }; return false
                    }
                })
            #expect(!settings.isEnabled)
            defaults.set(true, forKey: MeetingSpeakerSettings.preferenceKey)
            let restored = MeetingSpeakerSettings(store: store, defaults: defaults)
            #expect(await restored.isReadyForMeeting() == false)
            #expect(restored.isEnabled)
        }
    }
#endif
