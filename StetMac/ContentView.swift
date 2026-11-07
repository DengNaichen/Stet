import SwiftUI

struct ContentView: View {
    var body: some View {
        DictationView(
            viewModel: DictationViewModel(session: DictationSession(speechService: ConfigurableSpeechService.live())))
    }
}
