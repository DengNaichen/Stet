import Foundation
import Testing
@testable import StetMobile

struct RewriteSettingsViewModelTests {
    @MainActor
    @Test func reportsAnExistingLocalModel() async {
        let manager = TestLocalDictationModelManager(
            status: .ready(localURL: URL(fileURLWithPath: "/tmp/model.onnx"))
        )
        let viewModel = RewriteSettingsViewModel(
            settingsStore: RewriteSettingsStore(),
            localModelManagers: [.senseVoice: manager]
        )

        await viewModel.refreshLocalModelStatus(for: .senseVoice)

        #expect(viewModel.localModelState(for: .senseVoice) == .downloaded)
    }

    @MainActor
    @Test func failedDownloadCanBeRetried() async {
        let manager = TestLocalDictationModelManager(status: .notDownloaded, failingDownloads: 1)
        var didNotifyDictation = false
        let viewModel = RewriteSettingsViewModel(
            settingsStore: RewriteSettingsStore(),
            localModelManagers: [.whisperLargeV3Turbo: manager],
            onLocalModelReady: { model in
                didNotifyDictation = model == .whisperLargeV3Turbo
            }
        )

        await viewModel.downloadLocalModel(.whisperLargeV3Turbo)
        #expect(viewModel.localModelState(for: .whisperLargeV3Turbo) == .downloadFailed)
        #expect(!didNotifyDictation)

        await viewModel.downloadLocalModel(.whisperLargeV3Turbo)
        #expect(viewModel.localModelState(for: .whisperLargeV3Turbo) == .downloaded)
        #expect(didNotifyDictation)
    }

    @MainActor
    @Test func downloadedModelCanBeDeleted() async {
        let manager = TestLocalDictationModelManager(
            status: .ready(localURL: URL(fileURLWithPath: "/tmp/model.onnx"))
        )
        let viewModel = RewriteSettingsViewModel(
            settingsStore: RewriteSettingsStore(),
            localModelManagers: [.senseVoice: manager]
        )

        await viewModel.deleteLocalModel(.senseVoice)

        #expect(viewModel.localModelState(for: .senseVoice) == .notDownloaded)
        #expect(await manager.deleteCount == 1)
    }

    @MainActor
    @Test func reportsBothLocalModelsIndependently() async {
        let senseVoice = TestLocalDictationModelManager(status: .notDownloaded)
        let whisper = TestLocalDictationModelManager(
            status: .ready(localURL: URL(fileURLWithPath: "/tmp/whisper.bin"))
        )
        let viewModel = RewriteSettingsViewModel(
            settingsStore: RewriteSettingsStore(),
            localModelManagers: [
                .senseVoice: senseVoice,
                .whisperLargeV3Turbo: whisper,
            ]
        )

        await viewModel.refreshLocalModelStatuses()

        #expect(viewModel.localModelState(for: .senseVoice) == .notDownloaded)
        #expect(viewModel.localModelState(for: .whisperLargeV3Turbo) == .downloaded)
    }

    @MainActor
    @Test func selectedDictationModelIsPersistedAndForwarded() {
        let suiteName = "LocalDictationSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let dictationSettings = LocalDictationSettingsStore(defaults: defaults)
        var selectedModel: MobileDictationModel?
        let viewModel = RewriteSettingsViewModel(
            settingsStore: RewriteSettingsStore(),
            dictationSettingsStore: dictationSettings,
            localModelManagers: [:],
            onLocalModelSelected: { selectedModel = $0 }
        )

        dictationSettings.selectedModel = .whisperLargeV3Turbo
        viewModel.onDictationModelSelected()

        #expect(selectedModel == .whisperLargeV3Turbo)
        #expect(
            LocalDictationSettingsStore(defaults: defaults).selectedModel
                == .whisperLargeV3Turbo
        )
    }

    @Test func senseVoiceModelManagerDeletesDownloadedAssets() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StetModelDeletionTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for asset in SenseVoiceModelAsset.allCases {
            let url = directory.appendingPathComponent(asset.fileName, isDirectory: false)
            try Data([1]).write(to: url)
        }

        let manager = try SenseVoiceModelManager(modelsDirectory: directory)
        #expect(
            await manager.status(for: SenseVoiceModelManager.modelName)
                == .ready(
                    localURL: directory.appendingPathComponent(SenseVoiceModelAsset.model.fileName)
                ))

        try await manager.deleteModel(for: SenseVoiceModelManager.modelName)

        #expect(await manager.status(for: SenseVoiceModelManager.modelName) == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func whisperModelManagerFindsAndDeletesDownloadedModel() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StetWhisperModelDeletionTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let modelURL = directory.appendingPathComponent(WhisperModelManager.modelFileName)
        try Data([1]).write(to: modelURL)

        let manager = try WhisperModelManager(modelsDirectory: directory)
        #expect(
            await manager.status(for: WhisperModelManager.modelName)
                == .ready(localURL: modelURL)
        )

        try await manager.deleteModel(for: WhisperModelManager.modelName)

        #expect(await manager.status(for: WhisperModelManager.modelName) == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

@MainActor
private final class TestLocalDictationModelManager: LocalDictationModelManaging {
    private var currentStatus: ASRModelStatus
    private var failingDownloads: Int
    private(set) var deleteCount = 0

    init(status: ASRModelStatus, failingDownloads: Int = 0) {
        self.currentStatus = status
        self.failingDownloads = failingDownloads
    }

    func status() async -> ASRModelStatus {
        currentStatus
    }

    func download() async throws {
        if failingDownloads > 0 {
            failingDownloads -= 1
            currentStatus = .error(message: "internal download failure")
            throw TestLocalModelError.downloadFailed
        }
        currentStatus = .ready(localURL: URL(fileURLWithPath: "/tmp/model.onnx"))
    }

    func delete() async throws {
        deleteCount += 1
        currentStatus = .notDownloaded
    }
}

private enum TestLocalModelError: Error {
    case downloadFailed
}
