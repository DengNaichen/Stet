#if os(macOS)
    import CoreAudio
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Audio Device Change Monitor")
    struct AudioDeviceChangeMonitorTests {
        @Test func sharesRegistrationUntilLastClientStops() {
            let system = ListenerSystem()
            let center = NotificationCenter()
            let received = NotificationCount()
            let token = center.addObserver(
                forName: AudioDeviceChangeMonitor.devicesDidChangeNotification, object: nil, queue: nil
            ) { _ in MainActor.assumeIsolated { received.value += 1 } }
            defer { center.removeObserver(token) }
            let monitor = AudioDeviceChangeMonitor(system: system, notificationCenter: center)

            monitor.startMonitoring()
            monitor.startMonitoring()
            #expect(system.addCount == 1)
            #expect(system.delegates.count == 1)
            system.emitChange()
            #expect(received.value == 1)

            monitor.stopMonitoring()
            #expect(system.removeCount == 0)
            system.emitChange()
            #expect(received.value == 2)

            let delegate = system.delegates.first
            monitor.stopMonitoring()
            #expect(system.removeCount == 1)
            #expect(system.delegates.isEmpty)
            // An already enqueued callback must not notify after the last client stops.
            delegate?.propertiesChanged(properties: [PropertyAddress(kAudioHardwarePropertyDevices)])
            #expect(received.value == 2)
            monitor.stopMonitoring()
            #expect(system.removeCount == 1)

            monitor.startMonitoring()
            #expect(system.addCount == 2)
            system.emitChange()
            #expect(received.value == 3)
            monitor.stopMonitoring()
            #expect(system.removeCount == 2)
        }

        @Test func failedRegistrationCanRetryWithoutLeakingClientCount() {
            let system = ListenerSystem()
            let monitor = AudioDeviceChangeMonitor(system: system)
            system.failAdd = true
            monitor.startMonitoring()
            #expect(system.delegates.isEmpty)
            // Retry directly: a stop here would mask a leaked failed-start count.
            system.failAdd = false
            monitor.startMonitoring()
            #expect(system.addCount == 2)
            monitor.stopMonitoring()
            #expect(system.removeCount == 1)
            #expect(system.delegates.isEmpty)
        }

        @Test func failedRemovalRetriesWithoutDuplicateRegistration() {
            let system = ListenerSystem()
            let center = NotificationCenter()
            let received = NotificationCount()
            let token = center.addObserver(
                forName: AudioDeviceChangeMonitor.devicesDidChangeNotification, object: nil, queue: nil
            ) { _ in MainActor.assumeIsolated { received.value += 1 } }
            defer { center.removeObserver(token) }
            let monitor = AudioDeviceChangeMonitor(system: system, notificationCenter: center)
            monitor.startMonitoring()
            system.failRemove = true
            monitor.stopMonitoring()
            #expect(system.removeCount == 1)
            #expect(system.delegates.count == 1)
            system.emitChange()
            #expect(received.value == 0)

            monitor.startMonitoring()
            #expect(system.addCount == 1)
            system.emitChange()
            #expect(received.value == 1)
            system.failRemove = false
            monitor.stopMonitoring()
            #expect(system.removeCount == 2)
            #expect(system.delegates.isEmpty)
        }

        @Test func deinitRemovesRegistrationWithOutstandingClients() {
            let system = ListenerSystem()
            var monitor: AudioDeviceChangeMonitor? = AudioDeviceChangeMonitor(system: system)
            weak var releasedMonitor = monitor
            monitor?.startMonitoring()
            monitor?.startMonitoring()
            monitor = nil
            #expect(releasedMonitor == nil)
            #expect(system.removeCount == 1)
            #expect(system.delegates.isEmpty)
        }

    }

    @MainActor
    private final class NotificationCount {
        var value = 0
    }

    // Test instances are accessed synchronously on MainActor, including delegate delivery.
    private nonisolated final class ListenerSystem: AudioHardwareSystem, @unchecked Sendable {
        var addCount = 0
        var removeCount = 0
        var failAdd = false
        var failRemove = false

        init() { super.init(id: AudioObjectID(kAudioObjectSystemObject)) }

        override func addListener(forProperties properties: [AudioObjectPropertyAddress], dispatchQueue: DispatchQueue?)
            throws
        {
            checkRegistration(properties, dispatchQueue)
            addCount += 1
            if failAdd { throw AudioHardwareError(kAudioHardwareUnspecifiedError) }
        }

        override func removeListener(
            forProperties properties: [AudioObjectPropertyAddress], dispatchQueue: DispatchQueue?
        ) throws {
            checkRegistration(properties, dispatchQueue)
            removeCount += 1
            if failRemove { throw AudioHardwareError(kAudioHardwareUnspecifiedError) }
        }

        private func checkRegistration(_ properties: [AudioObjectPropertyAddress], _ queue: DispatchQueue?) {
            #expect(Thread.isMainThread)
            #expect(queue === DispatchQueue.main)
            #expect(properties.count == 1)
            #expect(properties.first?.mSelector == kAudioHardwarePropertyDevices)
            #expect(properties.first?.mScope == kAudioObjectPropertyScopeGlobal)
            #expect(properties.first?.mElement == kAudioObjectPropertyElementMain)
        }

        @MainActor func emitChange() {
            for delegate in delegates {
                delegate.propertiesChanged(properties: [PropertyAddress(kAudioHardwarePropertyDevices)])
            }
        }
    }
#endif
