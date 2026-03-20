#if os(macOS)
import AppKit
import AVFoundation

enum InteractionSoundPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case soft
    case glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft:
            return "Soft"
        case .glass:
            return "Glass"
        }
    }

    fileprivate var startPromptResourceName: String {
        switch self {
        case .soft:
            return "DictationStartSoft"
        case .glass:
            return "DictationStartGlass"
        }
    }

    fileprivate var finishSoundName: NSSound.Name {
        switch self {
        case .soft:
            return NSSound.Name("Morse")
        case .glass:
            return NSSound.Name("Hero")
        }
    }
}

@MainActor
protocol InteractionSoundPlaying: AnyObject {
    func playStartPrompt(preset: InteractionSoundPreset) async
    func playFinish(preset: InteractionSoundPreset)
    func playPreview(preset: InteractionSoundPreset)
}

private final class PromptSoundPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: @MainActor (Bool) -> Void

    init(onFinish: @escaping @MainActor (Bool) -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            onFinish(flag)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in
            onFinish(false)
        }
    }
}

@MainActor
final class InteractionSoundPlayer: InteractionSoundPlaying {
    private var activePromptPlayers: [UUID: AVAudioPlayer] = [:]
    private var activePromptDelegates: [UUID: PromptSoundPlaybackDelegate] = [:]

    func playStartPrompt(preset: InteractionSoundPreset) async {
        guard let promptURL = Bundle.main.url(
            forResource: preset.startPromptResourceName,
            withExtension: "wav"
        ) else {
            NSSound.beep()
            return
        }

        await withCheckedContinuation { continuation in
            do {
                let player = try AVAudioPlayer(contentsOf: promptURL)
                let identifier = UUID()
                let delegate = PromptSoundPlaybackDelegate { [weak self] _ in
                    guard let self else {
                        continuation.resume()
                        return
                    }

                    self.activePromptPlayers.removeValue(forKey: identifier)
                    self.activePromptDelegates.removeValue(forKey: identifier)
                    continuation.resume()
                }

                player.delegate = delegate
                player.prepareToPlay()
                activePromptPlayers[identifier] = player
                activePromptDelegates[identifier] = delegate

                guard player.play() else {
                    activePromptPlayers.removeValue(forKey: identifier)
                    activePromptDelegates.removeValue(forKey: identifier)
                    continuation.resume()
                    return
                }
            } catch {
                NSSound.beep()
                continuation.resume()
            }
        }
    }

    func playFinish(preset: InteractionSoundPreset) {
        playSystemSound(named: preset.finishSoundName)
    }

    func playPreview(preset: InteractionSoundPreset) {
        Task { @MainActor [weak self] in
            await self?.playStartPrompt(preset: preset)
        }
    }

    private func playSystemSound(named name: NSSound.Name) {
        if let sound = NSSound(named: name) {
            sound.play()
            return
        }

        NSSound.beep()
    }
}
#endif
