#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Audio Device Change Monitor")
    struct AudioDeviceChangeMonitorTests {
        @Test func sharedInstanceExists() {
            let monitor = AudioDeviceChangeMonitor.shared

            #expect(monitor != nil)
        }

        @Test func startMonitoringCanBeCalledMultipleTimes() {
            let monitor = AudioDeviceChangeMonitor()

            monitor.startMonitoring()
            monitor.startMonitoring()
            monitor.stopMonitoring()
            monitor.stopMonitoring()
        }

        @Test func stopMonitoringWithoutStartIsHarmless() {
            let monitor = AudioDeviceChangeMonitor()

            monitor.stopMonitoring()
        }

        @Test func notificationNameIsCorrect() {
            let notificationName = AudioDeviceChangeMonitor.devicesDidChangeNotification

            #expect(notificationName.rawValue == "AudioDevicesDidChange")
        }
    }
#endif
