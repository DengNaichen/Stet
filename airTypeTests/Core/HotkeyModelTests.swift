#if os(macOS)
import AppKit
import Carbon
import KeyboardShortcuts
import Testing

@testable import airType

@MainActor
@Suite("Hotkey Models", .serialized)
struct HotkeyModelTests {
    @Test func sidedModifierFlagsToggleAndFilter() {
        var flags: SidedModifierFlags = []
        flags = SidedModifierFlags.toggled(from: flags, keyCode: UInt16(kVK_RightShift))
        flags = SidedModifierFlags.toggled(from: flags, keyCode: UInt16(kVK_RightControl))

        let filtered = flags.filtered(by: [.shift])

        #expect(flags.contains(.rightShift))
        #expect(flags.contains(.rightControl))
        #expect(filtered == [.rightShift])
        #expect(flags.satisfies([.rightShift]))
        #expect(!flags.satisfies([.leftShift]))
    }

    @Test func dictationHotkeyRoundTripsThroughKeyboardShortcutsStorage() {
        let name = KeyboardShortcuts.Name.dictationHotkey
        let originalShortcut = KeyboardShortcuts.getShortcut(for: name)
        let testShortcut = KeyboardShortcuts.Shortcut(.k, modifiers: [.command])

        defer {
            KeyboardShortcuts.removeHandler(for: name)

            if let originalShortcut {
                KeyboardShortcuts.setShortcut(originalShortcut, for: name)
            } else {
                KeyboardShortcuts.reset(name)
            }
        }

        KeyboardShortcuts.setShortcut(testShortcut, for: name)

        #expect(KeyboardShortcuts.getShortcut(for: name) == testShortcut)
        #expect(name.shortcut == testShortcut)
        #expect(HotkeyBinding.dictation.name.shortcut == testShortcut)
    }

    @Test func dictationHotkeyRegistersAModifierPlusKeyShortcut() {
        let name = KeyboardShortcuts.Name.dictationHotkey
        let originalShortcut = KeyboardShortcuts.getShortcut(for: name)
        let testShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.control])

        defer {
            KeyboardShortcuts.removeHandler(for: name)

            if let originalShortcut {
                KeyboardShortcuts.setShortcut(originalShortcut, for: name)
            } else {
                KeyboardShortcuts.reset(name)
            }
        }

        KeyboardShortcuts.removeHandler(for: name)
        KeyboardShortcuts.setShortcut(testShortcut, for: name)

        var triggerCount = 0
        KeyboardShortcuts.onKeyDown(for: name) {
            triggerCount += 1
        }

        #expect(KeyboardShortcuts.getShortcut(for: name) == testShortcut)
        #expect(KeyboardShortcuts.isEnabled(for: name))
        #expect(triggerCount == 0)
    }
}
#endif
