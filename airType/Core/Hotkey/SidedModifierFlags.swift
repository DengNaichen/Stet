#if os(macOS)
import AppKit
import Carbon

struct SidedModifierFlags: OptionSet, Equatable, Codable, Sendable {
    let rawValue: Int

    nonisolated static let leftShift = SidedModifierFlags(rawValue: 1 << 0)
    nonisolated static let rightShift = SidedModifierFlags(rawValue: 1 << 1)
    nonisolated static let leftControl = SidedModifierFlags(rawValue: 1 << 2)
    nonisolated static let rightControl = SidedModifierFlags(rawValue: 1 << 3)
    nonisolated static let leftOption = SidedModifierFlags(rawValue: 1 << 4)
    nonisolated static let rightOption = SidedModifierFlags(rawValue: 1 << 5)
    nonisolated static let leftCommand = SidedModifierFlags(rawValue: 1 << 6)
    nonisolated static let rightCommand = SidedModifierFlags(rawValue: 1 << 7)

    nonisolated static let allShift: SidedModifierFlags = [.leftShift, .rightShift]
    nonisolated static let allControl: SidedModifierFlags = [.leftControl, .rightControl]
    nonisolated static let allOption: SidedModifierFlags = [.leftOption, .rightOption]
    nonisolated static let allCommand: SidedModifierFlags = [.leftCommand, .rightCommand]

    nonisolated static func sidedFlag(for keyCode: UInt16) -> SidedModifierFlags? {
        switch Int(keyCode) {
        case kVK_Shift:
            return .leftShift
        case kVK_RightShift:
            return .rightShift
        case kVK_Control:
            return .leftControl
        case kVK_RightControl:
            return .rightControl
        case kVK_Option:
            return .leftOption
        case kVK_RightOption:
            return .rightOption
        case kVK_Command:
            return .leftCommand
        case kVK_RightCommand:
            return .rightCommand
        default:
            return nil
        }
    }

    nonisolated static func genericModifier(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch Int(keyCode) {
        case kVK_Shift, kVK_RightShift:
            return .shift
        case kVK_Control, kVK_RightControl:
            return .control
        case kVK_Option, kVK_RightOption:
            return .option
        case kVK_Command, kVK_RightCommand:
            return .command
        default:
            return nil
        }
    }

    nonisolated static func toggled(from current: SidedModifierFlags, keyCode: UInt16) -> SidedModifierFlags {
        guard let flag = sidedFlag(for: keyCode) else { return current }
        if (current.rawValue & flag.rawValue) != 0 {
            return SidedModifierFlags(rawValue: current.rawValue & ~flag.rawValue)
        }
        return SidedModifierFlags(rawValue: current.rawValue | flag.rawValue)
    }

    nonisolated func filtered(by modifiers: NSEvent.ModifierFlags) -> SidedModifierFlags {
        var filteredRawValue = 0
        if modifiers.contains(.shift) {
            filteredRawValue |= rawValue & Self.allShift.rawValue
        }
        if modifiers.contains(.control) {
            filteredRawValue |= rawValue & Self.allControl.rawValue
        }
        if modifiers.contains(.option) {
            filteredRawValue |= rawValue & Self.allOption.rawValue
        }
        if modifiers.contains(.command) {
            filteredRawValue |= rawValue & Self.allCommand.rawValue
        }
        return SidedModifierFlags(rawValue: filteredRawValue)
    }

    nonisolated func satisfies(_ required: SidedModifierFlags) -> Bool {
        required.rawValue == 0 || (rawValue & required.rawValue) == required.rawValue
    }
}
#endif
