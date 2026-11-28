import Combine
import Foundation
import os

nonisolated struct DictationRoutingTelemetry: Equatable, Sendable {
    let routedLanguageCode: String
    let routingReason: LanguageRoutingReason
    let lidMs: Int?
    let analyzerPrepareMs: Int?
}

struct DictationTimingRecord: Equatable, Sendable, Identifiable {
    let id: String
    let recordedAt: Date
    let audioDurationMs: Int?
    let startMs: Int
    let localFinalizeMs: Int
    let rewriteMs: Int?
    let totalWaitMs: Int
    let routedLanguageCode: String?
    let routingReason: String?
    let lidMs: Int?
    let analyzerPrepareMs: Int?

    init(
        id: String,
        recordedAt: Date,
        audioDurationMs: Int?,
        startMs: Int,
        localFinalizeMs: Int,
        rewriteMs: Int?,
        totalWaitMs: Int,
        routedLanguageCode: String? = nil,
        routingReason: String? = nil,
        lidMs: Int? = nil,
        analyzerPrepareMs: Int? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.audioDurationMs = audioDurationMs
        self.startMs = startMs
        self.localFinalizeMs = localFinalizeMs
        self.rewriteMs = rewriteMs
        self.totalWaitMs = totalWaitMs
        self.routedLanguageCode = routedLanguageCode
        self.routingReason = routingReason
        self.lidMs = lidMs
        self.analyzerPrepareMs = analyzerPrepareMs
    }

    var summaryLine: String {
        let rewritePart = rewriteMs.map { "\($0)ms" } ?? "off"
        let audioPart = audioDurationMs.map { "\($0)ms" } ?? "n/a"
        var parts = [
            "session=\(id.prefix(8))",
            "audio=\(audioPart)",
            "start=\(startMs)ms",
        ]
        if let routedLanguageCode {
            let reasonPart = routingReason ?? "unknown"
            let lidPart = lidMs.map { "\($0)ms" } ?? "n/a"
            let prepPart = analyzerPrepareMs.map { "\($0)ms" } ?? "n/a"
            parts.append("lang=\(routedLanguageCode)(\(reasonPart))")
            parts.append("lid=\(lidPart)")
            parts.append("prep=\(prepPart)")
        }
        parts.append("localASR=\(localFinalizeMs)ms")
        parts.append("rewrite=\(rewritePart)")
        parts.append("totalWait=\(totalWaitMs)ms")
        return parts.joined(separator: " ")
    }

    static func formatDuration(ms: Int) -> String {
        if ms >= 1_000 {
            return String(format: "%.2fs", Double(ms) / 1_000.0)
        }
        return "\(ms)ms"
    }
}

@MainActor
final class DictationTimingStore: ObservableObject {
    static let shared = DictationTimingStore()

    @Published private(set) var latest: DictationTimingRecord?
    @Published private(set) var recent: [DictationTimingRecord] = []

    private let maxRecords = 15
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "NaichengDeng.StetMobile",
        category: "DictationTiming"
    )
    private let logFileURL: URL?

    init(logFileURL: URL? = nil) {
        self.logFileURL = logFileURL ?? Self.defaultLogFileURL()
    }

    func record(_ entry: DictationTimingRecord) {
        latest = entry
        recent.insert(entry, at: 0)
        if recent.count > maxRecords {
            recent.removeLast(recent.count - maxRecords)
        }

        let line = "[StetTiming] \(entry.summaryLine)"
        logger.notice("\(line, privacy: .public)")
        print(line)
        appendToDisk(line: "\(ISO8601DateFormatter().string(from: entry.recordedAt)) \(line)\n")
    }

    func clearHistory() {
        latest = nil
        recent = []
    }

    private func appendToDisk(line: String) {
        guard let logFileURL, let data = line.data(using: .utf8) else { return }
        let directory = logFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: logFileURL.path),
            let handle = try? FileHandle(forWritingTo: logFileURL)
        {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }

    private static func defaultLogFileURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dictation-timing.log")
    }
}
