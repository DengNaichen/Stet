#if os(macOS)
    import AppKit
    import Combine
    import Foundation
    import StetASR
    import StetCore

    @MainActor
    final class MacAudioSettingsViewModel: ObservableObject {
        static let speakerEnrollmentConsentCopy =
            "Only enroll a speaker after you have permission. Stet deletes each recording immediately after creating an aggregate voice profile stored only on this Mac."
        static let requiredEnrollmentClipCount = 3

        let deviceManager: AudioDeviceSelectionManager
        let microphoneTestViewModel: MicrophoneTestViewModel
        @Published var localTranscriptionEngine: StoredTranscriptionEngine = .default {
            didSet {
                guard hasLoadedState, oldValue != localTranscriptionEngine else { return }
                settingsStore.saveTranscriptionEngine(localTranscriptionEngine)
            }
        }
        @Published var isPassiveListeningEnabled = true {
            didSet {
                guard hasLoadedState, oldValue != isPassiveListeningEnabled else { return }
                settingsStore.savePassiveListeningEnabled(isPassiveListeningEnabled)
            }
        }

        @Published private(set) var isWhisperDownloaded = false
        @Published private(set) var isWhisperDownloading = false
        @Published private(set) var whisperErrorMessage: String?

        @Published private(set) var isParakeetDownloaded = false
        @Published private(set) var isParakeetDownloading = false
        @Published private(set) var parakeetErrorMessage: String?

        @Published private(set) var isFunASRNanoDownloaded = false
        @Published private(set) var isFunASRNanoDownloading = false
        @Published private(set) var funASRNanoErrorMessage: String?

        @Published private(set) var speakerProfiles: [SpeakerProfile] = []
        @Published var enrollmentName = ""
        @Published var enrollmentRole: SpeakerProfileRole = .owner
        @Published var hasSpeakerEnrollmentConsent = false
        @Published private(set) var enrollmentClipCount = 0
        @Published private(set) var isRecordingEnrollment = false
        @Published private(set) var isProcessingEnrollment = false
        @Published private(set) var enrollmentErrorMessage: String?
        @Published private(set) var enrollmentCompletionMessage: String?

        private let settingsStore: DictationSettingsStore
        private var hasLoadedState = false
        private let microphoneTestService: MicrophoneTestService
        private let speakerProfileStore: SpeakerProfileStore
        private let extractEnrollmentEmbedding: @Sendable (URL) async throws -> SpeakerEnrollmentEmbedding
        private var enrollmentEmbeddings: [SpeakerEnrollmentEmbedding] = []

        private let localWhisperModelManager: LocalWhisperModelManager
        private let fluidAudioModelManager: FluidAudioModelManager
        private let funASRNanoModelManager: FunASRNanoModelManager

        init(
            deviceManager: AudioDeviceSelectionManager = .shared,
            microphoneTestService: MicrophoneTestService = DefaultMicrophoneTestService.shared,
            settingsStore: DictationSettingsStore = DictationSettingsStore(),
            configuration: any ModelStorageConfiguration = UserDefaultsModelStorage(),
            speakerProfileStore: SpeakerProfileStore = SpeakerProfileStore(),
            extractEnrollmentEmbedding: (@Sendable (URL) async throws -> SpeakerEnrollmentEmbedding)? = nil
        ) {
            let defaultEmbeddingService = SpeakerEnrollmentEmbeddingService()
            self.deviceManager = deviceManager
            self.microphoneTestViewModel = MicrophoneTestViewModel(microphoneTestService: microphoneTestService)
            self.microphoneTestService = microphoneTestService
            self.settingsStore = settingsStore
            self.speakerProfileStore = speakerProfileStore
            self.extractEnrollmentEmbedding =
                extractEnrollmentEmbedding ?? { url in
                    try await defaultEmbeddingService.extract(from: url)
                }
            self.localWhisperModelManager = LocalWhisperModelManager(configuration: configuration)
            self.fluidAudioModelManager = FluidAudioModelManager()
            self.funASRNanoModelManager = FunASRNanoModelManager()
        }

        func onAppear() {
            hasLoadedState = false
            deviceManager.refreshDevices()
            AudioDeviceChangeMonitor.shared.startMonitoring()

            isWhisperDownloaded = (try? localWhisperModelManager.defaultModelReady()) ?? false
            isParakeetDownloaded = fluidAudioModelManager.isModelDownloaded()
            isFunASRNanoDownloaded = funASRNanoModelManager.isModelDownloaded()
            localTranscriptionEngine = settingsStore.loadTranscriptionEngine()
            isPassiveListeningEnabled = settingsStore.loadPassiveListeningEnabled()
            hasLoadedState = true
        }

        func onDisappear() {
            AudioDeviceChangeMonitor.shared.stopMonitoring()
        }

        var localTranscriptionEngineOptions: [StoredTranscriptionEngine] {
            StoredTranscriptionEngine.allCases
        }

        var canStartSpeakerEnrollment: Bool {
            let nameIsValid = !enrollmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasCapacity: Bool =
                switch enrollmentRole {
                case .owner:
                    !speakerProfiles.contains { $0.role == .owner }
                case .known:
                    speakerProfiles.filter { $0.role == .known }.count < 3 && speakerProfiles.count < 4
                }
            let hasConsent = enrollmentRole == .owner || hasSpeakerEnrollmentConsent
            return nameIsValid && hasCapacity && hasConsent && !isProcessingEnrollment && !isRecordingEnrollment
        }

        func loadSpeakerProfiles() async {
            do {
                speakerProfiles = try await speakerProfileStore.loadProfiles()
                enrollmentErrorMessage = nil
            } catch {
                enrollmentErrorMessage = error.localizedDescription
            }
        }

        func startSpeakerEnrollmentClip() async {
            enrollmentErrorMessage = nil
            enrollmentCompletionMessage = nil
            guard !isRecordingEnrollment, !isProcessingEnrollment else { return }
            guard !enrollmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                enrollmentErrorMessage = "Enter a speaker name before recording."
                return
            }
            guard enrollmentRole == .owner || hasSpeakerEnrollmentConsent else {
                enrollmentErrorMessage = "Confirm that you have permission to enroll this speaker."
                return
            }
            guard canStartSpeakerEnrollment else {
                enrollmentErrorMessage =
                    enrollmentRole == .owner
                    ? "Only one owner profile can be enrolled."
                    : "A maximum of three known speaker profiles can be enrolled."
                return
            }

            do {
                try await microphoneTestService.startRecording()
                isRecordingEnrollment = true
            } catch {
                enrollmentErrorMessage = error.localizedDescription
            }
        }

        func stopSpeakerEnrollmentClip() async {
            guard isRecordingEnrollment else { return }
            isRecordingEnrollment = false
            isProcessingEnrollment = true
            defer { isProcessingEnrollment = false }

            do {
                let recordingURL = try await microphoneTestService.stopRecording()
                defer { try? FileManager.default.removeItem(at: recordingURL) }

                let embedding = try await extractEnrollmentEmbedding(recordingURL)
                guard enrollmentEmbeddings.allSatisfy({ $0.model == embedding.model }) else {
                    throw SpeakerEmbeddingRecognizerError.modelMismatch
                }
                enrollmentEmbeddings.append(embedding)
                enrollmentClipCount = enrollmentEmbeddings.count

                if enrollmentEmbeddings.count == Self.requiredEnrollmentClipCount {
                    try await finishSpeakerEnrollment(using: embedding.model)
                }
            } catch {
                enrollmentErrorMessage = error.localizedDescription
            }
        }

        func deleteSpeakerProfile(id: UUID) async {
            do {
                try await speakerProfileStore.delete(id: id)
                speakerProfiles = try await speakerProfileStore.loadProfiles()
                enrollmentErrorMessage = nil
            } catch {
                enrollmentErrorMessage = error.localizedDescription
            }
        }

        func cancelSpeakerEnrollment() async {
            if isRecordingEnrollment {
                isRecordingEnrollment = false
                if let url = try? await microphoneTestService.stopRecording() {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            enrollmentEmbeddings.removeAll(keepingCapacity: false)
            enrollmentClipCount = 0
            isProcessingEnrollment = false
        }

        func downloadWhisperModel() {
            guard !isWhisperDownloading, !isWhisperDownloaded else { return }
            isWhisperDownloading = true
            whisperErrorMessage = nil

            Task { [localWhisperModelManager] in
                do {
                    try await localWhisperModelManager.installDefaultModel()
                    await MainActor.run {
                        self.isWhisperDownloaded = (try? localWhisperModelManager.defaultModelReady()) ?? false
                        self.isWhisperDownloading = false
                    }
                } catch {
                    await MainActor.run {
                        self.whisperErrorMessage = error.localizedDescription
                        self.isWhisperDownloading = false
                    }
                }
            }
        }

        func downloadParakeetModel() {
            guard !isParakeetDownloading, !isParakeetDownloaded else { return }
            isParakeetDownloading = true
            parakeetErrorMessage = nil

            Task { [fluidAudioModelManager] in
                do {
                    try await fluidAudioModelManager.downloadModel()
                    await MainActor.run {
                        self.isParakeetDownloaded = fluidAudioModelManager.isModelDownloaded()
                        self.isParakeetDownloading = false
                    }
                } catch {
                    await MainActor.run {
                        self.parakeetErrorMessage = error.localizedDescription
                        self.isParakeetDownloading = false
                    }
                }
            }
        }

        func downloadFunASRNanoModel() {
            guard !isFunASRNanoDownloading, !isFunASRNanoDownloaded else { return }
            isFunASRNanoDownloading = true
            funASRNanoErrorMessage = nil

            Task { [funASRNanoModelManager] in
                do {
                    try await funASRNanoModelManager.installDefaultModel()
                    await MainActor.run {
                        self.isFunASRNanoDownloaded = funASRNanoModelManager.isModelDownloaded()
                        self.isFunASRNanoDownloading = false
                    }
                } catch {
                    await MainActor.run {
                        self.funASRNanoErrorMessage = error.localizedDescription
                        self.isFunASRNanoDownloading = false
                    }
                }
            }
        }

        func openWhisperFolder() {
            revealInFinder(urlProvider: { try self.localWhisperModelManager.defaultModelURL() })
        }

        func openParakeetFolder() {
            revealInFinder(urlProvider: { self.fluidAudioModelManager.cacheDirectoryURL() })
        }

        func openFunASRNanoFolder() {
            revealInFinder(urlProvider: { try self.funASRNanoModelManager.modelsDirectoryURL() })
        }

        private func revealInFinder(urlProvider: @escaping () throws -> URL) {
            do {
                let providedURL = try urlProvider()
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: providedURL.path, isDirectory: &isDirectory)
                let url = exists && isDirectory.boolValue ? providedURL : providedURL.deletingLastPathComponent()
                NSWorkspace.shared.open(url)
            } catch {}
        }

        private func finishSpeakerEnrollment(using model: SpeakerEmbeddingModelIdentity) async throws {
            defer {
                enrollmentEmbeddings.removeAll(keepingCapacity: false)
                enrollmentClipCount = 0
            }
            let centroid = try SpeakerEmbeddingRecognizer.normalizedCentroid(
                enrollmentEmbeddings.map(\.normalizedVector)
            )
            let displayName = enrollmentName.trimmingCharacters(in: .whitespacesAndNewlines)
            try await speakerProfileStore.save(
                SpeakerProfile(
                    displayName: displayName,
                    role: enrollmentRole,
                    model: model,
                    normalizedCentroid: centroid,
                    enrollmentSampleCount: enrollmentEmbeddings.count,
                    matchThreshold: SpeakerProfile.defaultMatchThreshold
                )
            )
            speakerProfiles = try await speakerProfileStore.loadProfiles(currentModel: model)
            enrollmentCompletionMessage = "\(displayName) is enrolled."
            enrollmentName = ""
            hasSpeakerEnrollmentConsent = false
        }
    }
#endif
