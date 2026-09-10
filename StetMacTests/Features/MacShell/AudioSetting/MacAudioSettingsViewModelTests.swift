#if os(macOS)
    import FluidAudio
    import Foundation
    import StetASR
    import StetCore
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac Audio Settings View Model", .serialized)
    struct MacAudioSettingsViewModelTests {
        @Test func exposesAllLocalTranscriptionEngines() {
            let viewModel = MacAudioSettingsViewModel()

            #expect(
                viewModel.localTranscriptionEngineOptions == [
                    .fluidAudio,
                    .funASRNano,
                    .localWhisper,
                ]
            )
        }

        @Test func loadsAndPersistsSelectedLocalTranscriptionEngine() {
            let defaults = TestSupport.makeUserDefaults()
            let settingsStore = DictationSettingsStore(
                defaults: defaults,
                secretStore: TestSecretStore()
            )
            settingsStore.saveTranscriptionEngine(.localWhisper)
            let viewModel = MacAudioSettingsViewModel(
                settingsStore: settingsStore,
                configuration: UserDefaultsModelStorage(defaults: defaults)
            )

            viewModel.onAppear()
            defer { viewModel.onDisappear() }

            #expect(viewModel.localTranscriptionEngine == .localWhisper)
            #expect(settingsStore.loadTranscriptionEngine() == .localWhisper)

            viewModel.localTranscriptionEngine = .fluidAudio

            #expect(settingsStore.loadTranscriptionEngine() == .fluidAudio)
        }

        @Test func passiveListeningDefaultsOnAndPersistsExplicitChanges() {
            let defaults = TestSupport.makeUserDefaults()
            let settingsStore = DictationSettingsStore(
                defaults: defaults,
                secretStore: TestSecretStore()
            )
            let viewModel = MacAudioSettingsViewModel(
                settingsStore: settingsStore,
                configuration: UserDefaultsModelStorage(defaults: defaults)
            )

            viewModel.onAppear()
            defer { viewModel.onDisappear() }

            #expect(viewModel.isPassiveListeningEnabled)

            viewModel.isPassiveListeningEnabled = false

            #expect(!settingsStore.loadPassiveListeningEnabled())
            #expect(defaults.object(forKey: MacPreferences.passiveListeningEnabled) as? Bool == false)
        }

        @Test func enrollsOwnerAndConsentedKnownSpeakerThenDeletesKnownProfile() async throws {
            let persistence = SettingsSpeakerProfilePersistence()
            let microphone = SettingsMicrophoneTestService(recordingCount: 6)
            let model = SpeakerEmbeddingModelIdentity(
                modelID: "3d-speaker-campplus",
                revision: "test-revision",
                dimension: 2
            )
            let viewModel = MacAudioSettingsViewModel(
                microphoneTestService: microphone,
                speakerProfileStore: persistence.makeStore(),
                extractEnrollmentEmbedding: { url in
                    let index = Int(url.deletingPathExtension().lastPathComponent) ?? 0
                    return SpeakerEnrollmentEmbedding(
                        model: model,
                        normalizedVector: index < 3 ? [1, 0] : [0, 1]
                    )
                }
            )
            await viewModel.loadSpeakerProfiles()

            viewModel.enrollmentName = "Me"
            for _ in 0..<3 {
                await viewModel.startSpeakerEnrollmentClip()
                await viewModel.stopSpeakerEnrollmentClip()
            }

            #expect(viewModel.speakerProfiles.count == 1)
            #expect(viewModel.speakerProfiles[0].role == .owner)
            #expect(viewModel.speakerProfiles[0].enrollmentSampleCount == 3)
            #expect(viewModel.speakerProfiles[0].matchThreshold == SpeakerProfile.defaultMatchThreshold)

            viewModel.enrollmentRole = .known
            viewModel.enrollmentName = "  Alice  "
            viewModel.hasSpeakerEnrollmentConsent = true
            for _ in 0..<3 {
                await viewModel.startSpeakerEnrollmentClip()
                await viewModel.stopSpeakerEnrollmentClip()
            }

            let known = try #require(viewModel.speakerProfiles.first { $0.role == .known })
            #expect(known.displayName == "Alice")
            #expect(microphone.recordingURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })

            await viewModel.deleteSpeakerProfile(id: known.id)

            #expect(viewModel.speakerProfiles.map(\.role) == [.owner])
            #expect(try await persistence.makeStore().loadProfiles().map(\.role) == [.owner])
        }

        @Test func knownSpeakerEnrollmentRequiresExplicitConsent() async {
            let microphone = SettingsMicrophoneTestService(recordingCount: 1)
            let viewModel = MacAudioSettingsViewModel(
                microphoneTestService: microphone,
                speakerProfileStore: SettingsSpeakerProfilePersistence().makeStore(),
                extractEnrollmentEmbedding: { _ in
                    SpeakerEnrollmentEmbedding(
                        model: SpeakerEmbeddingModelIdentity(
                            modelID: "model",
                            revision: "revision",
                            dimension: 2
                        ),
                        normalizedVector: [1, 0]
                    )
                }
            )
            viewModel.enrollmentRole = .known
            viewModel.enrollmentName = "Alice"

            #expect(MacAudioSettingsViewModel.speakerEnrollmentConsentCopy.contains("permission"))
            #expect(MacAudioSettingsViewModel.speakerEnrollmentConsentCopy.contains("deletes"))

            await viewModel.startSpeakerEnrollmentClip()

            #expect(microphone.startCallCount == 0)
            #expect(viewModel.enrollmentErrorMessage?.contains("permission") == true)
        }

        @Test func enrollmentEmbeddingUsesOnlyVADApprovedSamples() {
            let segmentation = AudioSignalAnalyzer.VadSegmentation(
                samples: (0..<10).map(Float.init),
                sampleRate: 10,
                segments: [
                    VadSegment(startTime: 0.2, endTime: 0.5),
                    VadSegment(startTime: 0.7, endTime: 0.9),
                ]
            )

            let samples = SpeakerEnrollmentEmbeddingService.voicedSamples(from: segmentation)

            #expect(samples == [2, 3, 4, 7, 8])
        }

        @Test func enforcesOneOwnerAndThreeKnownProfileCapBeforeRecording() async throws {
            let persistence = SettingsSpeakerProfilePersistence()
            let store = persistence.makeStore()
            try await store.save(profile(role: .owner, name: "Me", centroid: [1, 0]))
            try await store.save(profile(role: .known, name: "A", centroid: [0, 1]))
            try await store.save(profile(role: .known, name: "B", centroid: [0, -1]))
            try await store.save(profile(role: .known, name: "C", centroid: [-1, 0]))
            let microphone = SettingsMicrophoneTestService(recordingCount: 1)
            let viewModel = MacAudioSettingsViewModel(
                microphoneTestService: microphone,
                speakerProfileStore: store,
                extractEnrollmentEmbedding: { _ in throw TestError.expected }
            )
            await viewModel.loadSpeakerProfiles()

            viewModel.enrollmentRole = .known
            viewModel.enrollmentName = "D"
            viewModel.hasSpeakerEnrollmentConsent = true
            #expect(!viewModel.canStartSpeakerEnrollment)
            await viewModel.startSpeakerEnrollmentClip()
            #expect(microphone.startCallCount == 0)

            viewModel.enrollmentRole = .owner
            #expect(!viewModel.canStartSpeakerEnrollment)
        }

        private func profile(
            role: SpeakerProfileRole,
            name: String,
            centroid: [Float]
        ) -> SpeakerProfile {
            SpeakerProfile(
                displayName: name,
                role: role,
                model: SpeakerEmbeddingModelIdentity(
                    modelID: "model",
                    revision: "revision",
                    dimension: 2
                ),
                normalizedCentroid: centroid,
                enrollmentSampleCount: 3,
                matchThreshold: 0.7
            )
        }
    }

    @MainActor
    private final class SettingsMicrophoneTestService: MicrophoneTestService {
        let recordingURLs: [URL]
        private var nextRecordingIndex = 0
        private(set) var startCallCount = 0

        init(recordingCount: Int) {
            recordingURLs = (0..<recordingCount).map { index in
                TestSupport.temporaryFileURL(String(index), ext: "wav")
            }
            for url in recordingURLs {
                try? Data([0]).write(to: url)
            }
        }

        func startRecording() async throws {
            startCallCount += 1
        }

        func stopRecording() async throws -> URL {
            defer { nextRecordingIndex += 1 }
            return recordingURLs[nextRecordingIndex]
        }

        func playRecording(at _: URL) async throws {}
        func stopPlayback() {}

        func makeAudioLevelStream() async -> AsyncStream<Double> {
            AsyncStream { $0.finish() }
        }
    }

    private final class SettingsSpeakerProfilePersistence: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?

        func makeStore() -> SpeakerProfileStore {
            SpeakerProfileStore(
                loadData: { self.lock.withLock { self.data } },
                saveData: { value in self.lock.withLock { self.data = value } },
                deleteData: { self.lock.withLock { self.data = nil } }
            )
        }
    }
#endif
