#if os(macOS)
    import Foundation
    import StetCore

    nonisolated struct PassiveSpeechActivity: Equatable, Sendable {
        let isSpeechActive: Bool
        let didSpeechEnd: Bool
    }

    nonisolated struct PassiveSpeakerMatch: Equatable, Sendable {
        let identity: CapturedSpeakerIdentity
        let similarity: Double?
    }

    nonisolated enum MacPassiveListeningState: Equatable, Sendable {
        case unavailable(String)
        case passiveArmed
        case passivePending
        case passiveRelevant(UUID)
        case active
    }

    nonisolated struct MacPassiveListeningConfiguration: Equatable, Sendable {
        static let sampleRate = 16_000

        let preRollSamples: Int
        let ownerVerificationWindowSamples: Int
        let ownerVerificationHopSamples: Int
        let minimumVoicedSamples: Int
        let pendingLookbackSamples: Int64
        let inactivitySamples: Int64
        let ownerAbsenceSamples: Int64
        let processingHardCapSamples: Int
        let turnPaddingSamples: Int

        init(
            preRollSeconds: Double = 0.4,
            ownerVerificationWindowSeconds: Double = 2,
            minimumVoicedSeconds: Double = 1.2,
            ownerVerificationHopSeconds: Double = 0.5,
            pendingLookbackSeconds: Double = 15,
            inactivitySeconds: Double = 10,
            ownerAbsenceSeconds: Double = 60,
            processingHardCapSeconds: Double = 30,
            turnPaddingSeconds: Double = 0.2
        ) {
            preRollSamples = Self.samples(preRollSeconds)
            ownerVerificationWindowSamples = Self.samples(ownerVerificationWindowSeconds)
            ownerVerificationHopSamples = Self.samples(ownerVerificationHopSeconds)
            minimumVoicedSamples = Self.samples(minimumVoicedSeconds)
            pendingLookbackSamples = Int64(Self.samples(pendingLookbackSeconds))
            inactivitySamples = Int64(Self.samples(inactivitySeconds))
            ownerAbsenceSamples = Int64(Self.samples(ownerAbsenceSeconds))
            processingHardCapSamples = Self.samples(processingHardCapSeconds)
            turnPaddingSamples = Self.samples(turnPaddingSeconds)
        }

        private static func samples(_ seconds: Double) -> Int {
            max(Int((seconds * Double(sampleRate)).rounded()), 1)
        }
    }

    nonisolated struct MacPassiveListeningDependencies: Sendable {
        let detectVoiceActivity: @Sendable ([Float]) async throws -> PassiveSpeechActivity
        let verifyOwner: @Sendable ([Float]) async throws -> PassiveSpeakerMatch
        let addDiarizedAudio: @Sendable ([Float]) async throws -> [PassiveDiarizedRegion]
        let finalizeDiarizedAudio: @Sendable () async throws -> [PassiveDiarizedRegion]
        let resetAnalysis: @Sendable () async -> Void
        let resetDiarization: @Sendable () async -> Void
        let identifySpeaker: @Sendable ([Float]) async throws -> PassiveSpeakerMatch
        let transcribeAudioFile: @Sendable (URL) async throws -> String
        let historyCreate: @Sendable (UUID, Date) async throws -> Void
        let historyUpdate: @Sendable (UUID, String, [CapturedSpeakerRegion]) async throws -> Void
        let historyFinish: @Sendable (UUID, Date, String, [CapturedSpeakerRegion]) async throws -> Void
        let historyFail: @Sendable (UUID, Date, String, String, [CapturedSpeakerRegion]) async throws -> Void
        let now: @Sendable () -> Date

        init(
            detectVoiceActivity: @escaping @Sendable ([Float]) async throws -> PassiveSpeechActivity,
            verifyOwner: @escaping @Sendable ([Float]) async throws -> PassiveSpeakerMatch,
            addDiarizedAudio: @escaping @Sendable ([Float]) async throws -> [PassiveDiarizedRegion],
            finalizeDiarizedAudio: @escaping @Sendable () async throws -> [PassiveDiarizedRegion],
            resetAnalysis: @escaping @Sendable () async -> Void,
            resetDiarization: @escaping @Sendable () async -> Void = {},
            identifySpeaker: @escaping @Sendable ([Float]) async throws -> PassiveSpeakerMatch,
            transcribeAudioFile: @escaping @Sendable (URL) async throws -> String,
            historyCreate: @escaping @Sendable (UUID, Date) async throws -> Void,
            historyUpdate: @escaping @Sendable (UUID, String, [CapturedSpeakerRegion]) async throws -> Void,
            historyFinish: @escaping @Sendable (UUID, Date, String, [CapturedSpeakerRegion]) async throws -> Void,
            historyFail: @escaping @Sendable (UUID, Date, String, String, [CapturedSpeakerRegion]) async throws -> Void,
            now: @escaping @Sendable () -> Date = Date.init
        ) {
            self.detectVoiceActivity = detectVoiceActivity
            self.verifyOwner = verifyOwner
            self.addDiarizedAudio = addDiarizedAudio
            self.finalizeDiarizedAudio = finalizeDiarizedAudio
            self.resetAnalysis = resetAnalysis
            self.resetDiarization = resetDiarization
            self.identifySpeaker = identifySpeaker
            self.transcribeAudioFile = transcribeAudioFile
            self.historyCreate = historyCreate
            self.historyUpdate = historyUpdate
            self.historyFinish = historyFinish
            self.historyFail = historyFail
            self.now = now
        }
    }

    actor MacPassiveListeningCoordinator {
        nonisolated static let temporaryAudioPrefix = "stet-passive-turn"

        nonisolated struct Snapshot: Equatable, Sendable {
            let state: MacPassiveListeningState
            let epoch: UInt64
            let bufferedRange: Range<Int64>?
            let bufferedSampleCount: Int
            let acceptedRange: Range<Int64>?
            let completedRegionCount: Int
        }

        private enum ProcessingFailure: Error {
            case identity
            case transcription
            case history

            var code: String {
                switch self {
                case .identity: "speaker_identity_failed"
                case .transcription: "transcription_failed"
                case .history: "history_failed"
                }
            }
        }

        private struct ResolvedTurn {
            var startSample: Int
            var endSample: Int
            var identity: CapturedSpeakerIdentity
            var identitySimilarity: Double?
            var activityConfidence: Double
            var isOverlap: Bool
        }

        private final class Conversation {
            let id: UUID
            let epoch: UInt64
            let startSample: Int64
            let startedAt: Date
            var samples: [Float] = []
            var lastSpeechSample: Int64
            var lastOwnerSample: Int64
            var lastVerificationSample: Int64
            var diarizedRegions: [PassiveDiarizedRegion] = []
            var completedRegions: [CapturedSpeakerRegion] = []
            var processedThroughSample = 0
            var isProcessingTurns = false
            var pendingCloseSample: Int64?
            var pendingTerminalState: MacPassiveListeningState?

            init(
                id: UUID,
                epoch: UInt64,
                startSample: Int64,
                startedAt: Date,
                lastSpeechSample: Int64,
                lastOwnerSample: Int64,
                lastVerificationSample: Int64
            ) {
                self.id = id
                self.epoch = epoch
                self.startSample = startSample
                self.startedAt = startedAt
                self.lastSpeechSample = lastSpeechSample
                self.lastOwnerSample = lastOwnerSample
                self.lastVerificationSample = lastVerificationSample
            }

            var endSample: Int64 {
                startSample + Int64(samples.count)
            }

            var rawText: String {
                completedRegions.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
            }

            func append(_ frame: AudioCaptureFrame) {
                let expectedStart = endSample
                if frame.startSample > expectedStart {
                    samples.append(contentsOf: repeatElement(0, count: Int(frame.startSample - expectedStart)))
                }
                let overlap = max(expectedStart - frame.startSample, 0)
                if overlap < frame.samples.count {
                    samples.append(contentsOf: frame.samples.dropFirst(Int(overlap)))
                }
            }
        }

        private let configuration: MacPassiveListeningConfiguration
        private let dependencies: MacPassiveListeningDependencies
        private var state: MacPassiveListeningState = .unavailable("notArmed")
        private var epoch: UInt64 = 0
        private var bufferedFrames: [AudioCaptureFrame] = []
        private var pendingStartedSample: Int64?
        private var recentVoiceSamples: [Float] = []
        private var lastVerificationSample: Int64?
        private var conversation: Conversation?

        init(
            configuration: MacPassiveListeningConfiguration = .init(),
            dependencies: MacPassiveListeningDependencies
        ) {
            self.configuration = configuration
            self.dependencies = dependencies
        }

        func arm(epoch: UInt64) async {
            self.epoch = epoch
            state = .passiveArmed
            clearTransientState()
            await dependencies.resetAnalysis()
        }

        func ingest(_ frame: AudioCaptureFrame) async {
            guard frame.epoch == epoch, state != .active else { return }
            await evaluateDeadlines(at: frame.startSample)
            guard frame.epoch == epoch, state != .active else { return }

            let activity: PassiveSpeechActivity
            do {
                activity = try await dependencies.detectVoiceActivity(frame.samples)
            } catch {
                await recover(code: "vad_failed", at: frame.endSample)
                return
            }
            guard frame.epoch == epoch, state != .active else { return }

            switch state {
            case .passiveArmed:
                if activity.isSpeechActive {
                    state = .passivePending
                    pendingStartedSample = frame.startSample
                    appendBuffered(frame, capacity: Int(configuration.pendingLookbackSamples))
                    await handlePotentialOwner(in: frame, speechActive: true)
                } else {
                    appendBuffered(frame, capacity: configuration.preRollSamples)
                }
            case .passivePending:
                appendBuffered(frame, capacity: Int(configuration.pendingLookbackSamples))
                await handlePotentialOwner(in: frame, speechActive: activity.isSpeechActive)
            case .passiveRelevant:
                await ingestRelevant(frame, activity: activity)
            case .unavailable, .active:
                break
            }

            if activity.didSpeechEnd, case .passiveRelevant = state {
                await processAvailableTurns()
            }
            await evaluateDeadlines(at: frame.endSample)
        }

        func advance(toSample sample: Int64) async {
            await evaluateDeadlines(at: sample)
        }

        func hotkeyDown(newEpoch: UInt64) async {
            let wasRelevant = state.isRelevant
            epoch = newEpoch
            state = .active
            clearPending()
            if wasRelevant {
                _ = await closeConversation(
                    at: conversation?.endSample ?? 0,
                    terminalState: .active
                )
            } else {
                conversation = nil
                await dependencies.resetAnalysis()
            }
        }

        func hotkeyUp(newEpoch: UInt64) async {
            await arm(epoch: newEpoch)
        }

        func setUnavailable(_ reason: String) async {
            if case .passiveRelevant = state {
                await failConversation(code: "capture_unavailable", at: conversation?.endSample ?? 0)
            }
            state = .unavailable(reason)
            clearTransientState()
            await dependencies.resetAnalysis()
        }

        func shutdown() async {
            if case .passiveRelevant = state {
                await closeConversation(at: conversation?.endSample ?? 0)
            }
            state = .unavailable("shutdown")
            clearTransientState()
            await dependencies.resetAnalysis()
        }

        func snapshot() -> Snapshot {
            Snapshot(
                state: state,
                epoch: epoch,
                bufferedRange: bufferedFrames.first.flatMap { first in
                    bufferedFrames.last.map { first.startSample..<$0.endSample }
                },
                bufferedSampleCount: bufferedFrames.reduce(0) { $0 + $1.samples.count },
                acceptedRange: conversation.map { $0.startSample..<$0.endSample },
                completedRegionCount: conversation?.completedRegions.count ?? 0
            )
        }

        nonisolated static func cleanupOrphanedTemporaryAudio(
            in directory: URL = FileManager.default.temporaryDirectory
        ) {
            guard
                let urls = try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )
            else { return }
            for url in urls
            where url.pathExtension == "wav"
                && url.deletingPathExtension().lastPathComponent.hasPrefix("\(temporaryAudioPrefix)-")
            {
                try? FileManager.default.removeItem(at: url)
            }
        }

        private func handlePotentialOwner(in frame: AudioCaptureFrame, speechActive: Bool) async {
            guard speechActive else { return }
            appendRecentVoice(frame.samples)
            guard recentVoiceSamples.count >= configuration.minimumVoicedSamples else { return }
            if let lastVerificationSample,
                frame.endSample - lastVerificationSample < Int64(configuration.ownerVerificationHopSamples)
            {
                return
            }

            let candidate = Array(recentVoiceSamples.suffix(configuration.ownerVerificationWindowSamples))
            let verificationEpoch = epoch
            let verificationState = state
            lastVerificationSample = frame.endSample
            let match: PassiveSpeakerMatch
            do {
                match = try await dependencies.verifyOwner(candidate)
            } catch {
                await recover(code: "speaker_verification_failed", at: frame.endSample)
                return
            }
            guard epoch == verificationEpoch, state == verificationState else { return }

            guard match.identity == .self else { return }
            switch state {
            case .passivePending:
                await openConversation(ownerSample: frame.endSample)
            case .passiveRelevant:
                conversation?.lastOwnerSample = frame.endSample
            default:
                break
            }
        }

        private func openConversation(ownerSample: Int64) async {
            guard state == .passivePending,
                let first = bufferedFrames.first
            else { return }
            let id = UUID()
            let conversation = Conversation(
                id: id,
                epoch: epoch,
                startSample: first.startSample,
                startedAt: dependencies.now(),
                lastSpeechSample: bufferedFrames.last?.endSample ?? ownerSample,
                lastOwnerSample: ownerSample,
                lastVerificationSample: lastVerificationSample ?? ownerSample
            )
            for frame in bufferedFrames {
                conversation.append(frame)
            }
            self.conversation = conversation
            state = .passiveRelevant(id)
            bufferedFrames.removeAll(keepingCapacity: false)
            pendingStartedSample = nil
            recentVoiceSamples.removeAll(keepingCapacity: true)
            lastVerificationSample = nil

            do {
                try await dependencies.historyCreate(id, conversation.startedAt)
            } catch {
                await failConversation(code: ProcessingFailure.history.code, at: ownerSample)
                return
            }
            guard self.conversation?.id == id, self.conversation?.epoch == epoch else { return }
            do {
                await dependencies.resetDiarization()
                conversation.diarizedRegions = try await dependencies.addDiarizedAudio(conversation.samples)
            } catch {
                await failConversation(code: "diarization_failed", at: ownerSample)
            }
        }

        private func ingestRelevant(
            _ frame: AudioCaptureFrame,
            activity: PassiveSpeechActivity
        ) async {
            guard let conversation else { return }
            conversation.append(frame)
            if activity.isSpeechActive {
                conversation.lastSpeechSample = frame.endSample
                appendRecentVoice(frame.samples)
            }

            do {
                let regions = try await dependencies.addDiarizedAudio(frame.samples)
                guard self.conversation?.id == conversation.id,
                    self.conversation?.epoch == conversation.epoch
                else { return }
                conversation.diarizedRegions = regions
            } catch {
                await failConversation(code: "diarization_failed", at: frame.endSample)
                return
            }
            await handlePotentialOwner(in: frame, speechActive: activity.isSpeechActive)
        }

        private func processAvailableTurns() async {
            guard let conversation, !conversation.isProcessingTurns else { return }
            conversation.isProcessingTurns = true

            do {
                try await process(
                    Self.normalizedRegions(conversation.diarizedRegions),
                    for: conversation
                )
            } catch let failure as ProcessingFailure {
                conversation.isProcessingTurns = false
                await failConversation(code: failure.code, at: conversation.endSample)
                return
            } catch {
                conversation.isProcessingTurns = false
                await failConversation(code: "transcription_failed", at: conversation.endSample)
                return
            }
            conversation.isProcessingTurns = false

            guard self.conversation?.id == conversation.id,
                let pendingCloseSample = conversation.pendingCloseSample,
                let pendingTerminalState = conversation.pendingTerminalState
            else { return }
            conversation.pendingCloseSample = nil
            conversation.pendingTerminalState = nil
            _ = await closeConversation(
                at: pendingCloseSample,
                terminalState: pendingTerminalState
            )
        }

        private func process(
            _ regions: [PassiveDiarizedRegion],
            for conversation: Conversation
        ) async throws {
            let candidates = regions.filter { $0.endSample > conversation.processedThroughSample }
            guard !candidates.isEmpty else { return }

            var turns: [ResolvedTurn] = []
            for region in candidates {
                let start = max(region.startSample, conversation.processedThroughSample)
                let end = min(region.endSample, conversation.samples.count)
                guard end > start else { continue }

                let match: PassiveSpeakerMatch
                if region.isOverlap || region.speakerTrack == nil {
                    match = PassiveSpeakerMatch(identity: .unresolved, similarity: nil)
                } else {
                    do {
                        match = try await dependencies.identifySpeaker(
                            Array(conversation.samples[start..<end])
                        )
                    } catch {
                        throw ProcessingFailure.identity
                    }
                }
                guard self.conversation?.id == conversation.id,
                    self.conversation?.epoch == conversation.epoch
                else { return }

                let turn = ResolvedTurn(
                    startSample: start,
                    endSample: end,
                    identity: match.identity,
                    identitySimilarity: match.similarity,
                    activityConfidence: region.activityConfidence,
                    isOverlap: region.isOverlap
                )
                if let lastIndex = turns.indices.last,
                    turns[lastIndex].endSample == turn.startSample,
                    turns[lastIndex].identity == turn.identity,
                    turns[lastIndex].isOverlap == turn.isOverlap
                {
                    turns[lastIndex].endSample = turn.endSample
                    turns[lastIndex].identitySimilarity = Self.maxOptional(
                        turns[lastIndex].identitySimilarity,
                        turn.identitySimilarity
                    )
                    turns[lastIndex].activityConfidence = max(
                        turns[lastIndex].activityConfidence,
                        turn.activityConfidence
                    )
                } else {
                    turns.append(turn)
                }
            }

            var previousPaddedEnd = conversation.processedThroughSample
            for index in turns.indices {
                let turn = turns[index]
                let paddedStart = max(
                    previousPaddedEnd,
                    turn.startSample - configuration.turnPaddingSamples
                )
                var paddedEnd = min(
                    conversation.samples.count,
                    turn.endSample + configuration.turnPaddingSamples
                )
                if index < turns.index(before: turns.endIndex) {
                    let next = turns[turns.index(after: index)]
                    paddedEnd = min(
                        paddedEnd,
                        max(turn.endSample, next.startSample - configuration.turnPaddingSamples)
                    )
                }
                guard paddedEnd > paddedStart else { continue }

                var chunkStart = paddedStart
                while chunkStart < paddedEnd {
                    let chunkEnd = min(
                        chunkStart + configuration.processingHardCapSamples,
                        paddedEnd
                    )
                    let samples = Array(conversation.samples[chunkStart..<chunkEnd])
                    let url: URL
                    do {
                        url = try AudioWavWriter.writePCM16MonoWav(
                            samples: samples,
                            filePrefix: Self.temporaryAudioPrefix
                        )
                    } catch {
                        throw ProcessingFailure.transcription
                    }

                    let text: String
                    do {
                        defer { try? FileManager.default.removeItem(at: url) }
                        text = try await dependencies.transcribeAudioFile(url)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } catch {
                        throw ProcessingFailure.transcription
                    }
                    guard !text.isEmpty else { throw ProcessingFailure.transcription }
                    guard self.conversation?.id == conversation.id,
                        self.conversation?.epoch == conversation.epoch
                    else { return }

                    conversation.completedRegions.append(
                        CapturedSpeakerRegion(
                            id: UUID(),
                            startMilliseconds: Self.milliseconds(chunkStart),
                            endMilliseconds: Self.milliseconds(chunkEnd),
                            speaker: turn.identity,
                            text: text,
                            identitySimilarity: turn.identitySimilarity,
                            activityConfidence: turn.activityConfidence,
                            isOverlap: turn.isOverlap
                        )
                    )
                    conversation.processedThroughSample = chunkEnd
                    do {
                        try await dependencies.historyUpdate(
                            conversation.id,
                            conversation.rawText,
                            conversation.completedRegions
                        )
                    } catch {
                        throw ProcessingFailure.history
                    }
                    chunkStart = chunkEnd
                }
                previousPaddedEnd = paddedEnd
            }
        }

        private func evaluateDeadlines(at sample: Int64) async {
            switch state {
            case .passivePending:
                if let pendingStartedSample,
                    sample - pendingStartedSample > configuration.pendingLookbackSamples
                {
                    clearPending()
                    state = .passiveArmed
                    await dependencies.resetAnalysis()
                }
            case .passiveRelevant:
                guard let conversation else { return }
                if sample - conversation.lastSpeechSample > configuration.inactivitySamples
                    || sample - conversation.lastOwnerSample > configuration.ownerAbsenceSamples
                {
                    _ = await closeConversation(at: sample)
                }
            default:
                break
            }
        }

        @discardableResult
        private func closeConversation(
            at sample: Int64,
            terminalState: MacPassiveListeningState = .passiveArmed
        ) async -> Bool {
            guard let conversation else { return false }
            if conversation.isProcessingTurns {
                conversation.pendingCloseSample = max(conversation.pendingCloseSample ?? sample, sample)
                conversation.pendingTerminalState = terminalState
                return true
            }
            conversation.isProcessingTurns = true

            do {
                conversation.diarizedRegions = try await dependencies.finalizeDiarizedAudio()
            } catch {
                conversation.isProcessingTurns = false
                await failConversation(code: "diarization_failed", at: sample, terminalState: terminalState)
                return false
            }
            guard self.conversation?.id == conversation.id else { return false }

            do {
                try await process(Self.normalizedRegions(conversation.diarizedRegions), for: conversation)
            } catch let failure as ProcessingFailure {
                conversation.isProcessingTurns = false
                await failConversation(code: failure.code, at: sample, terminalState: terminalState)
                return false
            } catch {
                conversation.isProcessingTurns = false
                await failConversation(code: "transcription_failed", at: sample, terminalState: terminalState)
                return false
            }

            let endedAt = conversation.startedAt.addingTimeInterval(
                Double(max(sample - conversation.startSample, 0))
                    / Double(MacPassiveListeningConfiguration.sampleRate)
            )
            do {
                try await dependencies.historyFinish(
                    conversation.id,
                    endedAt,
                    conversation.rawText,
                    conversation.completedRegions
                )
            } catch {
                conversation.isProcessingTurns = false
                await failConversation(
                    code: ProcessingFailure.history.code,
                    at: sample,
                    terminalState: terminalState
                )
                return false
            }
            guard self.conversation?.id == conversation.id else { return false }
            conversation.isProcessingTurns = false
            self.conversation = nil
            state = terminalState
            clearPending()
            await dependencies.resetAnalysis()
            return false
        }

        private func recover(code: String, at sample: Int64) async {
            if case .passiveRelevant = state {
                await failConversation(code: code, at: sample)
            } else {
                clearPending()
                state = .passiveArmed
                await dependencies.resetAnalysis()
            }
        }

        private func failConversation(
            code: String,
            at sample: Int64,
            terminalState: MacPassiveListeningState = .passiveArmed
        ) async {
            guard let conversation else {
                clearPending()
                state = terminalState
                await dependencies.resetAnalysis()
                return
            }
            let endedAt = conversation.startedAt.addingTimeInterval(
                Double(max(sample - conversation.startSample, 0))
                    / Double(MacPassiveListeningConfiguration.sampleRate)
            )
            try? await dependencies.historyFail(
                conversation.id,
                endedAt,
                code,
                conversation.rawText,
                conversation.completedRegions
            )
            guard self.conversation?.id == conversation.id else { return }
            self.conversation = nil
            state = terminalState
            clearPending()
            await dependencies.resetAnalysis()
        }

        private func appendBuffered(_ frame: AudioCaptureFrame, capacity: Int) {
            bufferedFrames.append(frame)
            var overflow = bufferedFrames.reduce(0) { $0 + $1.samples.count } - capacity
            while overflow > 0, let first = bufferedFrames.first {
                if first.samples.count <= overflow {
                    bufferedFrames.removeFirst()
                    overflow -= first.samples.count
                } else {
                    let boundary = first.startSample + Int64(overflow)
                    bufferedFrames[0] = first.split(at: boundary).after!
                    overflow = 0
                }
            }
        }

        private func appendRecentVoice(_ samples: [Float]) {
            recentVoiceSamples.append(contentsOf: samples)
            if recentVoiceSamples.count > configuration.ownerVerificationWindowSamples {
                recentVoiceSamples.removeFirst(
                    recentVoiceSamples.count - configuration.ownerVerificationWindowSamples
                )
            }
        }

        private func clearPending() {
            bufferedFrames.removeAll(keepingCapacity: false)
            pendingStartedSample = nil
            recentVoiceSamples.removeAll(keepingCapacity: true)
            lastVerificationSample = nil
        }

        private func clearTransientState() {
            clearPending()
            conversation = nil
        }

        private nonisolated static func milliseconds(_ samples: Int) -> Int {
            Int((Double(samples) * 1_000 / Double(MacPassiveListeningConfiguration.sampleRate)).rounded())
        }

        private nonisolated static func maxOptional(_ lhs: Double?, _ rhs: Double?) -> Double? {
            switch (lhs, rhs) {
            case (.some(let lhs), .some(let rhs)): max(lhs, rhs)
            case (.some(let value), .none), (.none, .some(let value)): value
            case (.none, .none): nil
            }
        }

        private nonisolated static func normalizedRegions(
            _ regions: [PassiveDiarizedRegion]
        ) -> [PassiveDiarizedRegion] {
            let valid = regions.filter {
                $0.startSample >= 0 && $0.endSample > $0.startSample
                    && $0.activityConfidence.isFinite
            }
            let boundaries = Set(valid.flatMap { [$0.startSample, $0.endSample] }).sorted()
            guard boundaries.count > 1 else { return [] }

            // ponytail: O(n²) is bounded by Sortformer's four tracks; replace only if that ceiling changes.
            var result: [PassiveDiarizedRegion] = []
            for index in 0..<(boundaries.count - 1) {
                let start = boundaries[index]
                let end = boundaries[index + 1]
                let active = valid.filter { $0.startSample < end && $0.endSample > start }
                guard !active.isEmpty else { continue }
                let tracks = Set(active.compactMap(\.speakerTrack))
                let overlap = active.contains(where: \.isOverlap) || tracks.count > 1
                let next = PassiveDiarizedRegion(
                    speakerTrack: overlap ? nil : active.first?.speakerTrack,
                    startSample: start,
                    endSample: end,
                    activityConfidence: active.map(\.activityConfidence).max() ?? 0,
                    identitySimilarity: nil,
                    isOverlap: overlap
                )
                if let lastIndex = result.indices.last,
                    result[lastIndex].endSample == next.startSample,
                    result[lastIndex].speakerTrack == next.speakerTrack,
                    result[lastIndex].isOverlap == next.isOverlap
                {
                    result[lastIndex].endSample = next.endSample
                    result[lastIndex].activityConfidence = max(
                        result[lastIndex].activityConfidence,
                        next.activityConfidence
                    )
                } else {
                    result.append(next)
                }
            }
            return result
        }
    }

    private extension MacPassiveListeningState {
        nonisolated var isRelevant: Bool {
            if case .passiveRelevant = self { true } else { false }
        }
    }
#endif
