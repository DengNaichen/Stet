import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    enum Tab: Hashable {
        case dictionary
        case dictation
        case settings
    }

    enum ExternalDictationFlow: Equatable {
        case none
        case capturing
        case returnGuide
    }

    @Published var selectedTab: Tab = .dictionary
    @Published private(set) var externalDictationFlow: ExternalDictationFlow = .none

    private let dictationViewModel: SenseVoiceViewModel
    private var completionObserver: AnyCancellable?

    init(dictationViewModel: SenseVoiceViewModel) {
        self.dictationViewModel = dictationViewModel
        completionObserver = dictationViewModel.$completedSessionId
            .compactMap { $0 }
            .sink { [weak self] _ in
                guard self?.externalDictationFlow == .capturing else { return }
                self?.externalDictationFlow = .returnGuide
            }
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard url.scheme == "stetmobile", url.host == "dictate" else { return false }
        selectedTab = .dictation
        externalDictationFlow = .capturing
        dictationViewModel.synchronizeExternalRequest()
        return true
    }

    func dismissExternalGuide() {
        externalDictationFlow = .none
    }
}
