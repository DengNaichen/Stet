import StetAI
#if os(macOS)
    import Foundation
    import StetCore

    extension MacAppModel {
        convenience init(
            compatibilityStore: AppCompatibilityStore? = nil,
            rewriteModelCatalog: RewriteModelCatalogSource = RewriteModelCatalogSource(.bundled)
        ) {
            let settingsStore = DictationSettingsStore(
                defaults: .standard, secretStore: SharedKeychainSecretStore.macOS(),
                rewriteModelCatalog: rewriteModelCatalog)
            let captureService = MacAudioCaptureService()
            let liveMeetingPhaseStore = MCPLiveMeetingPhaseStore()
            let notificationService = MacDictationCompletionNotificationService.shared
            let expectedMeetingCoordinator = ExpectedMeetingCoordinator(
                reminders: notificationService
            )
            let calendarClient = LiveEventKitClient()
            let calendarSelectionStore = SelectedCalendarStore()
            let scopedCalendarClient = ScopedCalendarClient(
                client: calendarClient,
                selectionStore: calendarSelectionStore
            )
            let calendarSyncController = CalendarSyncController(
                client: calendarClient,
                selectionStore: calendarSelectionStore,
                synchronizer: expectedMeetingCoordinator
            )
            let meetingRecordingRuntime = MacMeetingRecordingRuntime.live()
            let pasteboardRestoreCoordinator = PasteboardRestoreCoordinator()
            let clipboardService = SystemClipboardService()
            let correctionLearning = MacCorrectionLearningService.live(settingsStore: settingsStore)
            let textInjectionService = SystemTextInjectionService(
                clipboardService: clipboardService,
                pasteboardRestoreCoordinator: pasteboardRestoreCoordinator,
                correctionLearning: correctionLearning
            )
            self.init(
                speechService: ConfigurableSpeechService.live(
                    settingsStore: settingsStore,
                    captureService: captureService
                ),
                clipboardService: clipboardService,
                textInjectionService: textInjectionService,
                mediaPlaybackController: MacMediaPlaybackController(),
                systemAudioMuting: SystemAudioMuteController(),
                settingsStore: settingsStore,
                captureCoordinator: MacDictationCaptureCoordinator(
                    clipboardService: clipboardService,
                    textInjectionService: textInjectionService,
                    compatibilityStore: compatibilityStore ?? AppCompatibilityStore.live(),
                    pasteboardRestoreCoordinator: pasteboardRestoreCoordinator
                ),
                mcpServerController: StetMCPServerController.live(
                    livePhaseStore: liveMeetingPhaseStore,
                    expectedMeetings: expectedMeetingCoordinator,
                    calendarClient: scopedCalendarClient
                ),
                meetingRecordingRuntime: meetingRecordingRuntime,
                liveMeetingPhaseStore: liveMeetingPhaseStore,
                expectedMeetingCoordinator: expectedMeetingCoordinator,
                calendarSyncController: calendarSyncController
            )
        }

    }
#endif
