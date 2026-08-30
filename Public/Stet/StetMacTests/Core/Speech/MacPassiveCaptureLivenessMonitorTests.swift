#if os(macOS)
    import Testing

    @testable import Stet

    @Suite("Mac Passive Capture Liveness Monitor")
    struct MacPassiveCaptureLivenessMonitorTests {
        @Test func firstFrameControlsReadinessAndResetsTimeout() {
            var monitor = MacPassiveCaptureLivenessMonitor()
            monitor.start(at: 10)

            #expect(!monitor.hasReceivedFrame)
            #expect(!monitor.isTimedOut(at: 14.999))
            #expect(monitor.isTimedOut(at: 15))

            monitor.recordFrame(at: 14)

            #expect(monitor.hasReceivedFrame)
            #expect(!monitor.isTimedOut(at: 18.999))
            #expect(monitor.isTimedOut(at: 19))
        }

        @Test func stopAndRestartDiscardOldFrameTime() {
            var monitor = MacPassiveCaptureLivenessMonitor()
            monitor.start(at: 1)
            monitor.recordFrame(at: 4)
            monitor.stop()

            #expect(!monitor.hasReceivedFrame)
            #expect(!monitor.isTimedOut(at: 100))

            monitor.start(at: 100)

            #expect(!monitor.hasReceivedFrame)
            #expect(!monitor.isTimedOut(at: 104.999))
            #expect(monitor.isTimedOut(at: 105))
        }

        @Test func captureBridgeReportsProducerProgressWithoutAConsumer() {
            let bridge = AudioCaptureEventBridge()
            _ = bridge.makeStream()
            let initialPosition = bridge.currentSamplePosition()

            bridge.emit(samples: [0.1, 0.2, 0.3])

            #expect(bridge.currentSamplePosition() == initialPosition + 3)
        }

        @Test func producerProgressKeepsSlowConsumerFromTimingOut() {
            var monitor = MacPassiveCaptureLivenessMonitor()
            monitor.start(at: 10, samplePosition: 100)

            monitor.recordCaptureProgress(through: 200, at: 14)

            #expect(!monitor.isTimedOut(at: 18.999))
            #expect(monitor.isTimedOut(at: 19))
        }
    }
#endif
