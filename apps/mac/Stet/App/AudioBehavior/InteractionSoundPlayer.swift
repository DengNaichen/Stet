#if os(macOS)
import AppKit
import AVFoundation

enum InteractionSoundPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case soft
    case glass
    case tink
    case pop
    case purr
    case submarine

    static let defaultPreset: Self = .soft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft:
            return "Soft (Morse)"
        case .glass:
            return "Glass (Hero)"
        case .tink:
            return "Tink"
        case .pop:
            return "Pop"
        case .purr:
            return "Purr"
        case .submarine:
            return "Submarine"
        }
    }

    fileprivate var startPromptResourceName: String {
        switch self {
        case .soft:
            return "DictationStartSoft"
        case .glass:
            return "DictationStartGlass"
        case .tink, .pop, .purr, .submarine:
            // 这些使用系统音效，不需要自定义资源文件
            return ""
        }
    }

    fileprivate var finishPromptResourceName: String {
        switch self {
        case .soft:
            return "DictationEndSoft"
        case .glass, .tink, .pop, .purr, .submarine:
            return ""
        }
    }

    fileprivate var finishSoundName: NSSound.Name {
        switch self {
        case .soft:
            return NSSound.Name("Morse")
        case .glass:
            return NSSound.Name("Hero")
        case .tink:
            return NSSound.Name("Tink")
        case .pop:
            return NSSound.Name("Pop")
        case .purr:
            return NSSound.Name("Purr")
        case .submarine:
            return NSSound.Name("Submarine")
        }
    }
    
    fileprivate var startSoundName: NSSound.Name {
        switch self {
        case .soft:
            return NSSound.Name("Morse")
        case .glass:
            return NSSound.Name("Hero")
        case .tink:
            return NSSound.Name("Tink")
        case .pop:
            return NSSound.Name("Pop")
        case .purr:
            return NSSound.Name("Purr")
        case .submarine:
            return NSSound.Name("Submarine")
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
    private var activeSoundPlayers: [UUID: AVAudioPlayer] = [:]
    private var activeSoundDelegates: [UUID: PromptSoundPlaybackDelegate] = [:]

    func playStartPrompt(preset: InteractionSoundPreset) async {
        if preset.startPromptResourceName.isEmpty {
            playSystemSound(named: preset.startSoundName)
            return
        }

        await withCheckedContinuation { continuation in
            startBundledSoundPlayback(resourceName: preset.startPromptResourceName) { _ in
                continuation.resume()
            }
        }
    }

    func playFinish(preset: InteractionSoundPreset) {
        if !preset.finishPromptResourceName.isEmpty {
            startBundledSoundPlayback(resourceName: preset.finishPromptResourceName)
            return
        }

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

    private func startBundledSoundPlayback(
        resourceName: String,
        onFinish: (@MainActor (Bool) -> Void)? = nil
    ) {
        guard let soundURL = Bundle.main.url(forResource: resourceName, withExtension: "wav") else {
            NSSound.beep()
            onFinish?(false)
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: soundURL)
            let identifier = UUID()
            let delegate = PromptSoundPlaybackDelegate { [weak self] success in
                self?.activeSoundPlayers.removeValue(forKey: identifier)
                self?.activeSoundDelegates.removeValue(forKey: identifier)
                onFinish?(success)
            }

            player.delegate = delegate
            player.prepareToPlay()
            activeSoundPlayers[identifier] = player
            activeSoundDelegates[identifier] = delegate

            guard player.play() else {
                activeSoundPlayers.removeValue(forKey: identifier)
                activeSoundDelegates.removeValue(forKey: identifier)
                onFinish?(false)
                return
            }
        } catch {
            NSSound.beep()
            onFinish?(false)
        }
    }
}
#endif
