#if os(macOS)
    import Foundation
    import StetCore
    import Testing

    @testable import Stet

    @Suite("Mac Passive Listening Coordinator", .serialized)
    struct MacPassiveListeningCoordinatorTests {
        @Test func activeCaptureDefersAndCoalescesPassiveRestarts() {
            var gate = MacPassiveListeningRestartGate()

            let idleRestart = gate.requestRestart()
            let overlappingIdleRestart = gate.requestRestart()
            let restartWasInFlight = gate.isRestartInFlight
            gate.finishRestart()

            gate.beginActiveCapture()
            let firstRestart = gate.requestRestart()
            let secondRestart = gate.requestRestart()
            let restartAfterActive = gate.finishActiveCapture()
            let secondFinish = gate.finishActiveCapture()
            let restartAfterFinish = gate.requestRestart()

            #expect(idleRestart == .start)
            #expect(overlappingIdleRestart == .coalesced)
            #expect(restartWasInFlight)
            #expect(!gate.isActiveCaptureInProgress)
            #expect(firstRestart == .deferred)
            #expect(secondRestart == .deferred)
            #expect(restartAfterActive)
            #expect(!secondFinish)
            #expect(restartAfterFinish == .start)
        }

        @Test func sixtyMinutesOfSilenceKeepsOnlyPreRollAndSkipsInference() async {
            let verifier = TestPassiveVerifier(similarities: [])
            let diarizer = TestPassiveDiarizer(results: [])
            let nano = TestPassiveNano(results: [])
            let coordinator = MacPassiveListeningCoordinator(
                dependencies: dependencies(verifier: verifier, diarizer: diarizer, nano: nano)
            )
            await coordinator.arm(epoch: 7)

            await coordinator.ingest(frame(epoch: 7, start: 0, count: 1_600, value: 0))
            await coordinator.ingest(frame(epoch: 7, start: 57_600_000, count: 1_600, value: 0))

            let snapshot = await coordinator.snapshot()
            #expect(snapshot.state == .passiveArmed)
            #expect(snapshot.bufferedSampleCount <= 6_400)
            #expect(await verifier.frames.isEmpty)
            #expect(await diarizer.frames.isEmpty)
            #expect(await nano.fileSampleCounts.isEmpty)
        }

        @Test func pendingKeepsPreRollThenExpiresAfterFifteenSeconds() async {
            let verifier = TestPassiveVerifier(similarities: [0.2])
            let coordinator = MacPassiveListeningCoordinator(
                configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                dependencies: dependencies(verifier: verifier)
            )
            await coordinator.arm(epoch: 1)
            await coordinator.ingest(frame(epoch: 1, start: 0, count: 6_400, value: 0))
            await coordinator.ingest(frame(epoch: 1, start: 6_400, count: 1_600, value: 0.25))

            var snapshot = await coordinator.snapshot()
            #expect(snapshot.state == .passivePending)
            #expect(snapshot.bufferedRange == 0..<8_000)

            await coordinator.advance(toSample: 6_400 + 240_001)

            snapshot = await coordinator.snapshot()
            #expect(snapshot.state == .passiveArmed)
            #expect(snapshot.bufferedSampleCount == 0)
        }

        @Test func otherThenOwnerReplaysPendingAndOwnerFirstOpensImmediately() async {
            let history = TestPassiveHistory()
            let verifier = TestPassiveVerifier(similarities: [0.2, 0.9])
            let coordinator = MacPassiveListeningCoordinator(
                configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                dependencies: dependencies(verifier: verifier, history: history)
            )
            await coordinator.arm(epoch: 1)
            await coordinator.ingest(frame(epoch: 1, start: 0, count: 6_400, value: 0))
            await coordinator.ingest(frame(epoch: 1, start: 6_400, count: 1_600, value: 0.25))
            await coordinator.ingest(frame(epoch: 1, start: 8_000, count: 1_600, value: 0.25))

            var snapshot = await coordinator.snapshot()
            #expect(snapshot.state.isPassiveRelevant)
            #expect(snapshot.acceptedRange == 0..<9_600)
            #expect(await history.calls.count == 1)

            let ownerFirstHistory = TestPassiveHistory()
            let ownerFirst = MacPassiveListeningCoordinator(
                configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                dependencies: dependencies(
                    verifier: TestPassiveVerifier(similarities: [0.9, 0.9]),
                    history: ownerFirstHistory
                )
            )
            await ownerFirst.arm(epoch: 2)
            await ownerFirst.ingest(frame(epoch: 2, start: 100, count: 1_600, value: 0.25))

            snapshot = await ownerFirst.snapshot()
            #expect(snapshot.state.isPassiveRelevant)
            #expect(snapshot.acceptedRange == 100..<1_700)
            #expect(await ownerFirstHistory.calls.count == 1)
        }

        @Test func relevantConversationClosesOnInactivityOrOwnerAbsence() async {
            let region = PassiveDiarizedRegion(
                speakerTrack: 0,
                startSample: 0,
                endSample: 1_600,
                activityConfidence: 0.9,
                isOverlap: false
            )
            let inactivityHistory = TestPassiveHistory()
            let inactivity = MacPassiveListeningCoordinator(
                configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                dependencies: dependencies(
                    verifier: TestPassiveVerifier(similarities: [0.9]),
                    nano: TestPassiveNano(results: [.success("inactivity")]),
                    history: inactivityHistory,
                    diarizedRegions: [region]
                )
            )
            await inactivity.arm(epoch: 1)
            await inactivity.ingest(frame(epoch: 1, start: 0, count: 1_600, value: 0.25))
            await inactivity.advance(toSample: 161_601)

            #expect(await inactivity.snapshot().state == .passiveArmed)
            #expect(
                await inactivityHistory.calls.contains { call in
                    if case .finish = call { true } else { false }
                })

            let absenceHistory = TestPassiveHistory()
            let absenceVerifier = TestPassiveVerifier(similarities: [0.9] + Array(repeating: 0.2, count: 6))
            let absence = MacPassiveListeningCoordinator(
                configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                dependencies: dependencies(
                    verifier: absenceVerifier,
                    nano: TestPassiveNano(results: [.success("absence")]),
                    history: absenceHistory,
                    diarizedRegions: [region]
                )
            )
            await absence.arm(epoch: 2)
            await absence.ingest(frame(epoch: 2, start: 0, count: 1_600, value: 0.25))
            for second in stride(from: 9, through: 54, by: 9) {
                await absence.ingest(
                    frame(epoch: 2, start: Int64(second * 16_000), count: 1_600, value: 0.25)
                )
            }
            await absence.advance(toSample: 961_601)

            #expect(await absence.snapshot().state == .passiveArmed)
            #expect(
                await absenceHistory.calls.contains { call in
                    if case .finish = call { true } else { false }
                })
        }

        @Test func hardCapSplitsTurnsAndOverlapIsStoredOnceAsUnresolved() async throws {
            let history = TestPassiveHistory()
            let nano = TestPassiveNano(results: [.success("A"), .success("B")])
            let hardCapRegion = PassiveDiarizedRegion(
                speakerTrack: 0,
                startSample: 0,
                endSample: 560_000,
                activityConfidence: 0.9,
                isOverlap: false
            )
            let hardCap = MacPassiveListeningCoordinator(
                configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                dependencies: dependencies(
                    verifier: TestPassiveVerifier(similarities: [0.9, 0.9]),
                    nano: nano,
                    history: history,
                    diarizedRegions: [hardCapRegion]
                )
            )
            await hardCap.arm(epoch: 1)
            await hardCap.ingest(frame(epoch: 1, start: 0, count: 1_600, value: 0.25))
            await hardCap.ingest(frame(epoch: 1, start: 1_600, count: 558_400, value: 0.25))
            await hardCap.ingest(frame(epoch: 1, start: 560_000, count: 1, value: -1))

            let counts = await nano.fileSampleCounts
            #expect(counts.count == 2)
            #expect(counts.allSatisfy { $0 <= 480_000 })
            #expect(counts.reduce(0, +) >= 560_000)

            let overlapHistory = TestPassiveHistory()
            let overlapNano = TestPassiveNano(results: [.success("self"), .success("overlap"), .success("other")])
            let identity = TestPassiveIdentityMatcher(matches: [
                PassiveSpeakerMatch(identity: .self, similarity: 0.92),
                PassiveSpeakerMatch(identity: .other, similarity: 0.31),
            ])
            let overlapping = [
                PassiveDiarizedRegion(
                    speakerTrack: 0, startSample: 0, endSample: 32_000,
                    activityConfidence: 0.9, isOverlap: false),
                PassiveDiarizedRegion(
                    speakerTrack: 1, startSample: 16_000, endSample: 48_000,
                    activityConfidence: 0.8, isOverlap: false),
                PassiveDiarizedRegion(
                    speakerTrack: 2, startSample: 24_000, endSample: 40_000,
                    activityConfidence: 0.7, isOverlap: false),
            ]
            let overlap = MacPassiveListeningCoordinator(
                configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                dependencies: dependencies(
                    verifier: TestPassiveVerifier(similarities: [0.9]),
                    nano: overlapNano,
                    history: overlapHistory,
                    identity: identity,
                    diarizedRegions: overlapping
                )
            )
            await overlap.arm(epoch: 3)
            await overlap.ingest(frame(epoch: 3, start: 0, count: 64_000, value: 0.25))
            await overlap.ingest(frame(epoch: 3, start: 64_000, count: 1, value: -1))

            let update = try #require(
                await overlapHistory.calls.last { call in
                    if case .update = call { true } else { false }
                })
            guard case .update(_, _, let regions) = update else {
                Issue.record("Expected history update")
                return
            }
            #expect(regions.count == 3)
            #expect(regions.filter(\.isOverlap).count == 1)
            #expect(regions.filter(\.isOverlap).map(\.speaker) == [.unresolved])
        }

        @Test func emptyNanoTurnKeepsCompletedTextAndContinuesWithLaterTurns() async throws {
            let history = TestPassiveHistory()
            let nano = TestPassiveNano(results: [
                .success("first"),
                .success("   "),
                .success("third"),
            ])
            let identity = TestPassiveIdentityMatcher(matches: [
                PassiveSpeakerMatch(identity: .self, similarity: 0.92),
                PassiveSpeakerMatch(identity: .other, similarity: 0.31),
                PassiveSpeakerMatch(identity: .self, similarity: 0.91),
            ])
            let regions = [
                PassiveDiarizedRegion(
                    speakerTrack: 0, startSample: 0, endSample: 1_600,
                    activityConfidence: 0.9, isOverlap: false),
                PassiveDiarizedRegion(
                    speakerTrack: 1, startSample: 1_600, endSample: 3_200,
                    activityConfidence: 0.8, isOverlap: false),
                PassiveDiarizedRegion(
                    speakerTrack: 0, startSample: 3_200, endSample: 4_800,
                    activityConfidence: 0.9, isOverlap: false),
            ]
            let coordinator = MacPassiveListeningCoordinator(
                configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                dependencies: dependencies(
                    verifier: TestPassiveVerifier(similarities: [0.9, 0.9, 0.9]),
                    nano: nano,
                    history: history,
                    identity: identity,
                    diarizedRegions: regions
                )
            )
            await coordinator.arm(epoch: 1)
            await coordinator.ingest(frame(epoch: 1, start: 0, count: 1_600, value: 0.25))
            await coordinator.ingest(frame(epoch: 1, start: 1_600, count: 1_600, value: 0.25))
            await coordinator.ingest(frame(epoch: 1, start: 3_200, count: 1_600, value: 0.25))
            await coordinator.ingest(frame(epoch: 1, start: 4_800, count: 1, value: -1))
            await coordinator.advance(toSample: 164_801)

            #expect(await nano.fileSampleCounts.count == 3)
            let calls = await history.calls
            #expect(!calls.contains { if case .fail = $0 { true } else { false } })
            let finish = try #require(calls.last { if case .finish = $0 { true } else { false } })
            guard case .finish(_, let text, let completedRegions) = finish else {
                Issue.record("Expected completed passive history")
                return
            }
            #expect(text == "first third")
            #expect(completedRegions.map(\.text) == ["first", "third"])
        }

        @Test func allEmptyNanoConversationFailsThenNextConversationRecovers() async {
            let history = TestPassiveHistory()
            let nano = TestPassiveNano(results: [.success("   "), .success("recovered")])
            let region = PassiveDiarizedRegion(
                speakerTrack: 0,
                startSample: 0,
                endSample: 1_600,
                activityConfidence: 0.9,
                isOverlap: false
            )
            let coordinator = MacPassiveListeningCoordinator(
                configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                dependencies: dependencies(
                    verifier: TestPassiveVerifier(similarities: [0.9, 0.9]),
                    nano: nano,
                    history: history,
                    diarizedRegions: [region]
                )
            )
            await coordinator.arm(epoch: 1)
            await coordinator.ingest(frame(epoch: 1, start: 0, count: 1_600, value: 0.25))
            await coordinator.ingest(frame(epoch: 1, start: 1_600, count: 1, value: -1))
            await coordinator.advance(toSample: 161_601)

            #expect(await coordinator.snapshot().state == .passiveArmed)
            #expect(
                await history.calls.contains { call in
                    if case .fail(_, "transcription_failed", let regions) = call {
                        regions.isEmpty
                    } else {
                        false
                    }
                })

            await coordinator.ingest(frame(epoch: 1, start: 200_000, count: 1_600, value: 0.25))
            await coordinator.ingest(frame(epoch: 1, start: 201_600, count: 1, value: -1))
            await coordinator.advance(toSample: 361_601)

            #expect(await coordinator.snapshot().state == .passiveArmed)
            #expect(
                await history.calls.contains { call in
                    if case .finish(_, "recovered", let regions) = call {
                        regions.map(\.text) == ["recovered"]
                    } else {
                        false
                    }
                })
        }

        @Test func staleVerifierResultCannotOpenConversationAfterEpochChange() async {
            let verifier = SuspendedOwnerVerifier()
            let history = TestPassiveHistory()
            let coordinator = MacPassiveListeningCoordinator(
                configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                dependencies: dependencies(
                    history: history,
                    verifyOwner: { samples in try await verifier.verify(samples) }
                )
            )
            await coordinator.arm(epoch: 1)
            let ingestion = Task {
                await coordinator.ingest(frame(epoch: 1, start: 0, count: 1_600, value: 0.25))
            }
            #expect(await TestSupport.eventuallyAsync { await verifier.isWaiting })

            await coordinator.hotkeyDown(newEpoch: 2)
            await verifier.resume(
                with: PassiveSpeakerMatch(identity: .self, similarity: 0.9)
            )
            await ingestion.value

            #expect(await coordinator.snapshot().state == .active)
            #expect(await history.calls.isEmpty)
        }

        @Test func hotkeyTakeoverDiscardsArmedOrPendingAndSealsRelevantAudio() async {
            let armedHistory = TestPassiveHistory()
            let armed = MacPassiveListeningCoordinator(dependencies: dependencies(history: armedHistory))
            await armed.arm(epoch: 1)
            await armed.hotkeyDown(newEpoch: 2)
            #expect(await armed.snapshot().state == .active)
            #expect(await armed.snapshot().epoch == 2)
            #expect(await armedHistory.calls.isEmpty)

            let pendingHistory = TestPassiveHistory()
            let pending = MacPassiveListeningCoordinator(
                configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                dependencies: dependencies(
                    verifier: TestPassiveVerifier(similarities: [0.2]),
                    history: pendingHistory
                )
            )
            await pending.arm(epoch: 3)
            await pending.ingest(frame(epoch: 3, start: 0, count: 1_600, value: 0.25))
            #expect(await pending.snapshot().state == .passivePending)
            await pending.hotkeyDown(newEpoch: 4)
            #expect(await pending.snapshot().state == .active)
            #expect(await pending.snapshot().bufferedSampleCount == 0)
            #expect(await pendingHistory.calls.isEmpty)

            let relevantHistory = TestPassiveHistory()
            let relevant = MacPassiveListeningCoordinator(
                configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                dependencies: dependencies(
                    verifier: TestPassiveVerifier(similarities: [0.9]),
                    nano: TestPassiveNano(results: [.success("relevant")]),
                    history: relevantHistory,
                    diarizedRegions: [
                        PassiveDiarizedRegion(
                            speakerTrack: 0,
                            startSample: 0,
                            endSample: 1_600,
                            activityConfidence: 0.9,
                            isOverlap: false
                        )
                    ]
                )
            )
            await relevant.arm(epoch: 5)
            await relevant.ingest(frame(epoch: 5, start: 0, count: 1_600, value: 0.25))
            await relevant.hotkeyDown(newEpoch: 6)
            #expect(await relevant.snapshot().state == .active)
            #expect(
                await relevantHistory.calls.contains { call in
                    if case .finish = call { true } else { false }
                })

            await relevant.hotkeyUp(newEpoch: 7)
            #expect(await relevant.snapshot().state == .passiveArmed)
            #expect(await relevant.snapshot().epoch == 7)
        }

        @Test func eachInferenceFailureClearsTransientStateAndAllowsNextOwner() async {
            for stage in FailureStage.allCases {
                let failure = FailOnce(stage: stage)
                let history = TestPassiveHistory()
                let dependencies = MacPassiveListeningDependencies(
                    detectVoiceActivity: { samples in
                        try await failure.failIfNeeded(.vad)
                        return activity(for: samples)
                    },
                    verifyOwner: { _ in
                        try await failure.failIfNeeded(.verification)
                        return PassiveSpeakerMatch(identity: .self, similarity: 0.9)
                    },
                    addDiarizedAudio: { _ in
                        try await failure.failIfNeeded(.diarization)
                        return [
                            PassiveDiarizedRegion(
                                speakerTrack: 0, startSample: 0, endSample: 1_600,
                                activityConfidence: 0.9, isOverlap: false)
                        ]
                    },
                    finalizeDiarizedAudio: { [] },
                    resetAnalysis: {},
                    identifySpeaker: { _ in
                        try await failure.failIfNeeded(.identity)
                        return PassiveSpeakerMatch(identity: .self, similarity: 0.9)
                    },
                    transcribeAudioFile: { _ in
                        try await failure.failIfNeeded(.transcription)
                        return "ok"
                    },
                    historyCreate: { id, _ in await history.record(.create(id)) },
                    historyUpdate: { id, text, regions in await history.record(.update(id, text, regions)) },
                    historyFinish: { id, _, text, regions in await history.record(.finish(id, text, regions)) },
                    historyFail: { id, _, code, _, regions in await history.record(.fail(id, code, regions)) }
                )
                let coordinator = MacPassiveListeningCoordinator(
                    configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                    dependencies: dependencies
                )
                await coordinator.arm(epoch: 1)
                await coordinator.ingest(frame(epoch: 1, start: 0, count: 1_600, value: 0.25))
                if stage == .identity || stage == .transcription {
                    await coordinator.ingest(frame(epoch: 1, start: 1_600, count: 1, value: -1))
                }
                #expect(await coordinator.snapshot().state == .passiveArmed)

                await coordinator.ingest(frame(epoch: 1, start: 3_200, count: 1_600, value: 0.25))
                #expect(await coordinator.snapshot().state.isPassiveRelevant)
            }
        }

        @Test func eightHourMixedTimelineStaysBoundedAndKeepsActiveRangesDisjoint() async {
            let verifierFailure = FailOnce(stage: .verification)
            let nano = TestPassiveNano(results: [.success("before"), .success("after")])
            let history = TestPassiveHistory()
            let region = PassiveDiarizedRegion(
                speakerTrack: 0,
                startSample: 0,
                endSample: 1_600,
                activityConfidence: 0.9,
                isOverlap: false
            )
            let coordinator = MacPassiveListeningCoordinator(
                configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                dependencies: dependencies(
                    nano: nano,
                    history: history,
                    diarizedRegions: [region],
                    verifyOwner: { samples in
                        if samples.last == 0.5 {
                            try await verifierFailure.failIfNeeded(.verification)
                        }
                        return PassiveSpeakerMatch(
                            identity: samples.last == 0.9 ? .self : .other,
                            similarity: samples.last == 0.9 ? 0.92 : 0.2
                        )
                    }
                )
            )

            var epoch: UInt64 = 1
            await coordinator.arm(epoch: epoch)
            for hour in 0..<8 {
                let hourStart = Int64(hour) * 3_600 * 16_000
                await coordinator.ingest(frame(epoch: epoch, start: hourStart, count: 1_600, value: 0))
                await coordinator.ingest(
                    frame(epoch: epoch, start: hourStart + 6_400, count: 1_600, value: 0.2)
                )
                await coordinator.advance(toSample: hourStart + 246_401)

                if hour == 3 {
                    #expect(await history.calls.isEmpty)
                    #expect(await nano.fileSampleCounts.isEmpty)

                    await coordinator.ingest(
                        frame(epoch: epoch, start: hourStart + 300_000, count: 1_600, value: 0.5)
                    )
                    #expect(await coordinator.snapshot().state == .passiveArmed)

                    await coordinator.ingest(
                        frame(epoch: epoch, start: hourStart + 310_000, count: 1_600, value: 0.9)
                    )
                    let firstPassiveRange = await coordinator.snapshot().acceptedRange
                    let activeStart = firstPassiveRange?.upperBound ?? 0

                    epoch += 1
                    await coordinator.hotkeyDown(newEpoch: epoch)
                    let activeEnd = activeStart + 32_000
                    await coordinator.ingest(
                        frame(epoch: epoch, start: activeStart, count: 32_000, value: 0.2)
                    )

                    epoch += 1
                    await coordinator.hotkeyUp(newEpoch: epoch)
                    await coordinator.ingest(
                        frame(epoch: epoch, start: activeEnd, count: 1_600, value: 0.9)
                    )
                    let secondPassiveRange = await coordinator.snapshot().acceptedRange
                    #expect(firstPassiveRange?.upperBound == activeStart)
                    #expect(secondPassiveRange?.lowerBound == activeEnd)
                    #expect(firstPassiveRange?.upperBound ?? .max <= secondPassiveRange?.lowerBound ?? .min)

                    await coordinator.ingest(
                        frame(epoch: epoch, start: activeEnd + 1_600, count: 1, value: -1)
                    )
                    await coordinator.advance(toSample: activeEnd + 161_602)
                }

                #expect(await coordinator.snapshot().bufferedSampleCount <= 6_400)
            }

            let calls = await history.calls
            #expect(calls.filter { if case .create = $0 { true } else { false } }.count == 2)
            #expect(await nano.fileSampleCounts.count == 2)
            #expect(await coordinator.snapshot().state == .passiveArmed)
        }

        @Test func temporaryTurnAudioIsRemovedAndCrashCleanupUsesExactPrefix() async throws {
            for result in [Result<String, TestError>.success("ok"), .failure(.expected)] {
                let nano = TestPassiveNano(results: [result])
                let coordinator = MacPassiveListeningCoordinator(
                    configuration: .init(minimumVoicedSeconds: 0.1, ownerVerificationHopSeconds: 0.1),
                    dependencies: dependencies(
                        verifier: TestPassiveVerifier(similarities: [0.9]),
                        nano: nano,
                        diarizedRegions: [
                            PassiveDiarizedRegion(
                                speakerTrack: 0,
                                startSample: 0,
                                endSample: 1_600,
                                activityConfidence: 0.9,
                                isOverlap: false
                            )
                        ]
                    )
                )
                await coordinator.arm(epoch: 1)
                await coordinator.ingest(frame(epoch: 1, start: 0, count: 1_600, value: 0.25))
                await coordinator.ingest(frame(epoch: 1, start: 1_600, count: 1, value: -1))

                let urls = await nano.fileURLs
                #expect(!urls.isEmpty)
                #expect(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
            }

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let orphan = directory.appendingPathComponent("stet-passive-turn-orphan.wav")
            let unrelated = directory.appendingPathComponent("stet-passive-turnish.wav")
            try Data().write(to: orphan)
            try Data().write(to: unrelated)

            MacPassiveListeningCoordinator.cleanupOrphanedTemporaryAudio(in: directory)

            #expect(!FileManager.default.fileExists(atPath: orphan.path))
            #expect(FileManager.default.fileExists(atPath: unrelated.path))
        }

        private func dependencies(
            verifier: TestPassiveVerifier = TestPassiveVerifier(similarities: [0.9]),
            diarizer: TestPassiveDiarizer = TestPassiveDiarizer(results: []),
            nano: TestPassiveNano = TestPassiveNano(results: []),
            history: TestPassiveHistory = TestPassiveHistory(),
            identity: TestPassiveIdentityMatcher = TestPassiveIdentityMatcher(matches: []),
            diarizedRegions: [PassiveDiarizedRegion] = [],
            verifyOwner: (@Sendable ([Float]) async throws -> PassiveSpeakerMatch)? = nil
        ) -> MacPassiveListeningDependencies {
            MacPassiveListeningDependencies(
                detectVoiceActivity: { samples in activity(for: samples) },
                verifyOwner: verifyOwner ?? { samples in
                    let similarity = try await verifier.verify(samples)
                    return PassiveSpeakerMatch(
                        identity: similarity >= 0.7 ? .self : .other,
                        similarity: similarity
                    )
                },
                addDiarizedAudio: { samples in
                    if diarizedRegions.isEmpty {
                        return try await diarizer.diarize(samples).map {
                            PassiveDiarizedRegion(
                                speakerTrack: $0.track,
                                startSample: Int($0.startSample),
                                endSample: Int($0.endSample),
                                activityConfidence: $0.activityConfidence,
                                isOverlap: $0.isOverlap
                            )
                        }
                    }
                    return diarizedRegions
                },
                finalizeDiarizedAudio: { diarizedRegions },
                resetAnalysis: {},
                identifySpeaker: { samples in
                    if await identity.hasMatches {
                        return try await identity.identify(samples)
                    }
                    return PassiveSpeakerMatch(identity: .self, similarity: 0.9)
                },
                transcribeAudioFile: { url in try await nano.transcribe(fileURL: url) },
                historyCreate: { id, _ in await history.record(.create(id)) },
                historyUpdate: { id, text, regions in await history.record(.update(id, text, regions)) },
                historyFinish: { id, _, text, regions in await history.record(.finish(id, text, regions)) },
                historyFail: { id, _, code, _, regions in await history.record(.fail(id, code, regions)) }
            )
        }

        private func frame(
            epoch: UInt64,
            start: Int64,
            count: Int,
            value: Float
        ) -> AudioCaptureFrame {
            AudioCaptureFrame(
                epoch: epoch,
                startSample: start,
                samples: Array(repeating: value, count: count)
            )
        }
    }

    private func activity(for samples: [Float]) -> PassiveSpeechActivity {
        if samples.first == -1 {
            return PassiveSpeechActivity(isSpeechActive: false, didSpeechEnd: true)
        }
        return PassiveSpeechActivity(
            isSpeechActive: samples.contains { $0 != 0 },
            didSpeechEnd: false
        )
    }

    private extension MacPassiveListeningState {
        var isPassiveRelevant: Bool {
            if case .passiveRelevant = self { true } else { false }
        }
    }

    private actor TestPassiveIdentityMatcher {
        private var matches: [PassiveSpeakerMatch]

        init(matches: [PassiveSpeakerMatch]) {
            self.matches = matches
        }

        var hasMatches: Bool { !matches.isEmpty }

        func identify(_: [Float]) throws -> PassiveSpeakerMatch {
            guard !matches.isEmpty else { throw TestError.expected }
            return matches.removeFirst()
        }
    }

    private actor SuspendedOwnerVerifier {
        private var continuation: CheckedContinuation<PassiveSpeakerMatch, Error>?

        var isWaiting: Bool { continuation != nil }

        func verify(_: [Float]) async throws -> PassiveSpeakerMatch {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }

        func resume(with match: PassiveSpeakerMatch) {
            continuation?.resume(returning: match)
            continuation = nil
        }
    }

    private enum FailureStage: CaseIterable {
        case vad
        case verification
        case diarization
        case identity
        case transcription
    }

    private actor FailOnce {
        let stage: FailureStage
        private var didFail = false

        init(stage: FailureStage) {
            self.stage = stage
        }

        func failIfNeeded(_ currentStage: FailureStage) throws {
            if currentStage == stage, !didFail {
                didFail = true
                throw TestError.expected
            }
        }
    }
#endif
