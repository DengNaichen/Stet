#if os(macOS)
    import Combine
    import CoreAudio
    import Foundation
    import Observation
    import os
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Observable presentation models")
    struct MacObservableViewModelTests {
        @Test func updateStateInvalidatesObservationWithoutAQueueHop() {
            let coordinator = UpdateCoordinator()
            let model = MacAppUpdateViewModel(coordinator: coordinator)
            #expect(model.state == .idle)
            let changed = observe { _ = model.isChecking }

            model.checkForUpdates()

            #expect(changed.withLock { $0 })
            #expect(model.state == .checking)
            #expect(model.isChecking)
            #expect(!model.canCheckForUpdates)
            model.setAutomaticallyChecksForUpdates(false)
            #expect(!model.automaticallyChecksForUpdates)
        }

        @Test func generalSettingsReceivesTheNewUpdateSnapshotSynchronously() {
            let coordinator = UpdateCoordinator()
            let model = MacAppUpdateViewModel(coordinator: coordinator)
            let settings = MacGeneralSettingsViewModel(defaults: TestSupport.makeUserDefaults())
            settings.configure(appModel: GeneralSettingsCoordinator(), appUpdateManager: model)

            coordinator.checkForUpdates()

            #expect(settings.updateSettings.isCheckingForUpdates)
            #expect(!settings.updateSettings.canCheckForUpdates)
        }

        @Test func meetingAndCalendarChangesInvalidateTheirDisplayedValues() async {
            let coordinator = MeetingCoordinator()
            let model = MacMeetingViewModel(coordinator: coordinator)
            let changed = observe { _ = model.meetingToggleTitle }

            coordinator.meetingSnapshot.meetingRecordingPhase = .recording(startedAt: Date(), folderName: "Test")

            #expect(changed.withLock { $0 })
            #expect(model.meetingToggleTitle == "Stop Meeting Recording")
            #expect(model.isMeetingBusy)
            #expect(model.canToggleMeetingRecording)
            let processingChanged = observe { _ = model.canToggleMeetingRecording }
            coordinator.meetingSnapshot.meetingRecordingPhase = .processing
            #expect(processingChanged.withLock { $0 })
            #expect(!model.canToggleMeetingRecording)

            let calendarChanged = observe { _ = model.calendarSyncState }
            await model.setCalendarMeetingsEnabled(true)
            #expect(calendarChanged.withLock { $0 })
            #expect(model.isCalendarMeetingsEnabled)
            #expect(model.calendarAuthorizationStatus == .fullAccess)
            #expect(model.calendarSyncState == coordinator.calendarSyncState)
            await model.setSelectedCalendarIDs(["work"])
            #expect(model.selectedCalendarIDs == ["work"])
            // Selection can change while calendar syncing is disabled, without a state event.
            coordinator.publishesUpdates = false
            await model.setCalendarMeetingsEnabled(false)
            await model.setSelectedCalendarIDs([])
            #expect(!model.isCalendarMeetingsEnabled)
            #expect(model.selectedCalendarIDs.isEmpty)
            model.toggleMeetingRecording()
            #expect(coordinator.toggleCount == 1)
        }

        @Test func compatibilityRefreshObservesTheEmittedValue() async {
            let store = AppCompatibilityStore(fetch: {
                Data(#"{"schemaVersion":1,"revision":999,"bundleIDs":[]}"#.utf8)
            })
            let model = MacCompatibilityViewModel(store: store)
            let changed = observe { _ = model.refreshState }

            await model.refresh()

            #expect(changed.withLock { $0 })
            #expect(model.refreshState == .updated)
            await model.refresh()
            #expect(model.refreshState == .upToDate)
        }

        @Test func deviceMenusStayInSyncWhenAnotherViewSelectsOrRefreshesDevices() {
            let provider = DeviceProvider()
            let manager = AudioDeviceSelectionManager(provider: provider, defaults: TestSupport.makeUserDefaults())
            let menu = AudioInputDeviceListViewModel(deviceManager: manager)
            let settings = AudioInputDeviceListViewModel(deviceManager: manager)
            let changed = observe { _ = menu.selectedDevice }

            settings.selectDevice(provider.external)

            #expect(changed.withLock { $0 })
            #expect(menu.selectedDevice == provider.external)
            let devicesChanged = observe { _ = settings.externalDevices }
            provider.devices = [provider.builtIn]
            menu.refreshDevices()
            #expect(devicesChanged.withLock { $0 })
            #expect(settings.externalDevices.isEmpty)
            #expect(menu.selectedDevice == provider.builtIn)
            #expect(settings.selectedDevice == provider.builtIn)
        }

        private func observe(_ read: () -> Void) -> OSAllocatedUnfairLock<Bool> {
            let changed = OSAllocatedUnfairLock(initialState: false)
            withObservationTracking(read, onChange: { changed.withLock { $0 = true } })
            return changed
        }
    }

    @MainActor
    private final class UpdateCoordinator: MacAppUpdateCoordinating {
        @Published var updateSnapshot = MacAppUpdateSnapshot(
            state: .idle, isConfigured: true, canCheckForUpdates: true, automaticallyChecksForUpdates: true)
        var updateSnapshots: AnyPublisher<MacAppUpdateSnapshot, Never> { $updateSnapshot.eraseToAnyPublisher() }
        func checkForUpdates() {
            updateSnapshot.state = .checking
            updateSnapshot.canCheckForUpdates = false
        }
        func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
            updateSnapshot.automaticallyChecksForUpdates = enabled
        }
    }

    @MainActor
    private final class MeetingCoordinator: MacMeetingCoordinating {
        let meetingSpeakerSettings = MeetingSpeakerSettings(store: MeetingSpeakerModelStore())
        @Published var meetingSnapshot = MacMeetingSnapshot(
            meetingRecordingPhase: .idle, isCalendarMeetingsEnabled: false,
            calendarAuthorizationStatus: .denied, calendarSyncState: .disabled, selectedCalendarIDs: [])
        var publishesUpdates = true
        var meetingSnapshots: AnyPublisher<MacMeetingSnapshot, Never> {
            $meetingSnapshot.filter { [self] _ in publishesUpdates }.eraseToAnyPublisher()
        }
        var toggleCount = 0
        var isCalendarMeetingsEnabled: Bool { meetingSnapshot.isCalendarMeetingsEnabled }
        var calendarAuthorizationStatus: CalendarAuthorizationStatus { meetingSnapshot.calendarAuthorizationStatus }
        var calendarSyncState: CalendarSyncState { meetingSnapshot.calendarSyncState }
        var selectedCalendarIDs: Set<String> { meetingSnapshot.selectedCalendarIDs }
        func availableCalendars() throws -> [CalendarRecord] { [] }
        func toggleMeetingRecording() { toggleCount += 1 }
        func setCalendarMeetingsEnabled(_ enabled: Bool) async {
            meetingSnapshot.isCalendarMeetingsEnabled = enabled
            meetingSnapshot.calendarAuthorizationStatus = .fullAccess
            meetingSnapshot.calendarSyncState = enabled ? .active(Date()) : .disabled
        }
        func setSelectedCalendarIDs(_ ids: Set<String>) async { meetingSnapshot.selectedCalendarIDs = ids }
    }

    @MainActor
    private final class GeneralSettingsCoordinator: MacGeneralSettingsAppModeling {
        var isDebugForceOnboardingEnabled = false
        func setLaunchAtLoginEnabled(_ enabled: Bool) throws {}
        func refreshRuntimeFromSettings() {}
        func applyDockVisibility(showInDock: Bool) {}
        func setDebugForceOnboardingEnabled(_ enabled: Bool) {}
        func resetOnboardingForDebug() {}
    }

    private final class DeviceProvider: AudioDeviceProviding, @unchecked Sendable {
        let builtIn = Stet.AudioHardwareDevice(
            id: 1, uid: "built-in", name: "Built-in", transportType: kAudioDeviceTransportTypeBuiltIn)
        let external = Stet.AudioHardwareDevice(
            id: 2, uid: "usb", name: "USB", transportType: kAudioDeviceTransportTypeUSB)
        var devices: [Stet.AudioHardwareDevice]?
        func allInputDevices() -> [Stet.AudioHardwareDevice] { devices ?? [builtIn, external] }
        func defaultInputDevice() -> Stet.AudioHardwareDevice? { builtIn }
    }
#endif
