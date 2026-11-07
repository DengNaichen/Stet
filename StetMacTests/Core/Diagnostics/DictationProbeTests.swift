import Foundation
import Testing

@testable import Stet

@Suite("Dictation Probe Ordering")
struct DictationProbeTests {
    @Test func runtimeMarksAreRecordedBeforeEndRunReturns() throws {
        let lines = ProbeTraceRecorder()
        let probe = DictationRuntimeProbe(onTrace: { lines.append($0) })
        probe.beginRun(trigger: "test", source: "test", panelVisible: false)
        probe.markCaptureStartRequested()
        probe.markPanelShown()
        probe.endRun(reason: "complete")

        try #require(lines.values.count == 4)
        #expect(lines.values[0].contains("stage=run_began"))
        #expect(lines.values[1].contains("stage=capture_start_requested"))
        #expect(lines.values[2].contains("stage=panel_shown"))
        #expect(lines.values[3].contains("stage=run_ended"))
    }

    @Test func startupTimingUsesSynchronousEventTimes() throws {
        let lines = ProbeTraceRecorder()
        let clock = ProbeClock()
        let probe = DictationStartupProbe(now: { clock.time }, onTrace: { lines.append($0) })
        probe.begin(trigger: .hotkey)
        clock.advance(by: 0.025)
        probe.record(.panelShown)
        clock.advance(by: 0.050)
        probe.record(.listeningStateEntered)
        probe.record(.firstBufferWritten)
        probe.record(.cancelled)

        try #require(lines.values.count == 4)
        #expect(lines.values[1].contains("sinceStartMs=25.0 sincePreviousStageMs=25.0"))
        #expect(lines.values[2].contains("sinceStartMs=75.0 sincePreviousStageMs=50.0"))
        #expect(lines.values[3].contains("stage=first_buffer_written"))
    }
}

private nonisolated final class ProbeTraceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var values: [String] { lock.withLock { stored } }
    func append(_ line: String) { lock.withLock { stored.append(line) } }
}

private nonisolated final class ProbeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: TimeInterval = 10
    var time: TimeInterval { lock.withLock { stored } }
    func advance(by interval: TimeInterval) { lock.withLock { stored += interval } }
}
