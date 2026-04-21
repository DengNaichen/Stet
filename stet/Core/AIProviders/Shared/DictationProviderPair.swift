import Foundation

struct DictationProviderPair: Sendable, Equatable {
    let transcriptionProvider: DictationProvider
    let rewriteProvider: DictationProvider
}
