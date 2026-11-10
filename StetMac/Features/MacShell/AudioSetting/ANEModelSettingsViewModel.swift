import Combine
import Foundation

@MainActor
final class ANEModelSettingsViewModel: ObservableObject {
    @Published private(set) var status = ANEModelInstallationStatus(
        supported: false, ready: false, canPrepareInstalled: false, downloadAvailable: false)
    @Published private(set) var phase: ANEInstallationProgress?
    @Published private(set) var isBusy = false
    @Published private(set) var isCancelling = false
    @Published private(set) var errorMessage: String?
    private let installer: any ANEModelInstalling
    private var operation: Task<Void, Never>?
    private var operationID: UUID?

    init(installer: any ANEModelInstalling) { self.installer = installer }

    func refresh() async { status = await installer.status() }

    var statusText: String {
        if isCancelling { return String(localized: "Canceling preparation…") }
        switch phase {
        case .copying: return String(localized: "Getting the acceleration model…")
        case .compiling: return String(localized: "Preparing the model for this Mac…")
        case .waitingForIdle: return String(localized: "Waiting for the current transcription to finish…")
        case .preparing(let completed, let total):
            return String(localized: "Preparing acceleration: \(completed) of \(total)")
        case .ready, .disabled, nil:
            if !status.supported { return String(localized: "Requires Apple Silicon and macOS 15 or later.") }
            return status.ready ? String(localized: "Enabled") : String(localized: "Using CPU")
        }
    }

    func importCandidate(at url: URL) {
        let installer = installer
        start { progress in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try await installer.importCandidate(at: url, progress: progress)
        }
    }

    func download() {
        let installer = installer
        start { try await installer.download(progress: $0) }
    }

    func prepareInstalled() {
        let installer = installer
        start { try await installer.prepareInstalled(progress: $0) }
    }

    func disable() {
        let installer = installer
        start { try await installer.disable(progress: $0) }
    }

    func cancel() {
        guard isBusy else { return }
        isCancelling = true
        operation?.cancel()
    }

    private func start(
        _ work: @escaping @Sendable (@escaping @Sendable (ANEInstallationProgress) -> Void) async throws -> Void
    ) {
        guard !isBusy else { return }
        let id = UUID()
        operationID = id
        isBusy = true
        isCancelling = false
        errorMessage = nil
        phase = nil
        operation = Task { [weak self] in
            do {
                try await work { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.operationID == id else { return }
                        self.phase = value
                    }
                }
            } catch is CancellationError {
                // The installer leaves CPU files and completed downloads intact.
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            guard let self else { return }
            await self.refresh()
            self.operationID = nil
            self.phase = nil
            self.isBusy = false
            self.isCancelling = false
            self.operation = nil
        }
    }
}
