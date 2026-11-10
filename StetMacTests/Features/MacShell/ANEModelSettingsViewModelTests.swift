import Foundation
import Testing
@testable import Stet

@MainActor
struct ANEModelSettingsViewModelTests {
    @Test func importPublishesReadinessOnlyAfterCompletionAndCoalescesClicks() async throws {
        let installer = ANESettingsInstallerStub(mode: .success)
        let model = ANEModelSettingsViewModel(installer: installer)
        await model.refresh()
        #expect(!model.status.downloadAvailable)
        model.importCandidate(at: URL(fileURLWithPath: "/tmp/ane-candidate"))
        model.importCandidate(at: URL(fileURLWithPath: "/tmp/ane-candidate"))
        #expect(model.isBusy)
        #expect(!model.status.ready)
        try #require(await TestSupport.eventually { !model.isBusy })
        #expect(model.status.ready)
        #expect(model.errorMessage == nil)
        #expect(await installer.imports == 1)
    }

    @Test func cancellationClearsBusyStateAndRejectsLateProgress() async throws {
        let installer = ANESettingsInstallerStub(mode: .wait)
        let model = ANEModelSettingsViewModel(installer: installer)
        model.importCandidate(at: URL(fileURLWithPath: "/tmp/ane-candidate"))
        try #require(await TestSupport.eventuallyAsync { await installer.imports == 1 })
        model.cancel()
        #expect(model.isCancelling)
        try #require(await TestSupport.eventually { !model.isBusy })
        await installer.emitLateProgress()
        await Task.yield()
        #expect(!model.status.ready)
        #expect(model.phase == nil)
        #expect(model.errorMessage == nil)
    }

    @Test func failedPreparationShowsErrorAndKeepsCPUStatus() async throws {
        let model = ANEModelSettingsViewModel(installer: ANESettingsInstallerStub(mode: .failure))
        model.prepareInstalled()
        try #require(await TestSupport.eventually { !model.isBusy })
        #expect(!model.status.ready)
        #expect(model.errorMessage != nil)
    }
}

private actor ANESettingsInstallerStub: ANEModelInstalling {
    enum Mode { case success, wait, failure }
    let mode: Mode
    var imports = 0
    var ready = false
    var progress: (@Sendable (ANEInstallationProgress) -> Void)?
    init(mode: Mode) { self.mode = mode }
    func status() -> ANEModelInstallationStatus {
        ANEModelInstallationStatus(supported: true, ready: ready, canPrepareInstalled: true, downloadAvailable: false)
    }
    func importCandidate(at directory: URL, progress: @escaping @Sendable (ANEInstallationProgress) -> Void)
        async throws
    {
        imports += 1
        self.progress = progress
        try await prepareInstalled(progress: progress)
    }
    func prepareInstalled(progress: @escaping @Sendable (ANEInstallationProgress) -> Void) async throws {
        progress(.preparing(0, 4))
        switch mode {
        case .success: try await Task.sleep(for: .milliseconds(50)); ready = true
        case .wait: try await Task.sleep(for: .seconds(30))
        case .failure: throw ANEModelInstallError.invalidModel
        }
    }
    func download(progress: @escaping @Sendable (ANEInstallationProgress) -> Void) async throws {
        throw ANEModelInstallError.unavailable
    }
    func disable(progress: @escaping @Sendable (ANEInstallationProgress) -> Void) async throws { ready = false }
    func emitLateProgress() { progress?(.ready) }
}
