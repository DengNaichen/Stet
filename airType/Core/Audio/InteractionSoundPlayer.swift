#if os(macOS)
import AppKit

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

    fileprivate var startSoundName: NSSound.Name {
        switch self {
        case .soft:
            return NSSound.Name("Submarine")
        case .glass:
            return NSSound.Name("Glass")
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
struct InteractionSoundPlayer {
    func playStart(preset: InteractionSoundPreset) {
        play(named: preset.startSoundName)
    }

    func playFinish(preset: InteractionSoundPreset) {
        play(named: preset.finishSoundName)
    }

    func playPreview(preset: InteractionSoundPreset) {
        playStart(preset: preset)
    }

    private func play(named name: NSSound.Name) {
        if let sound = NSSound(named: name) {
            sound.play()
            return
        }

        NSSound.beep()
    }
}
#endif
