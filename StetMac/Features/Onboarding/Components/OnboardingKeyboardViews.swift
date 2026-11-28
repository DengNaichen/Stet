#if os(macOS)
    import AppKit
    import ApplicationServices
    import Combine
    import KeyboardShortcuts
    import SwiftUI

    final class OnboardingKeyboardMonitor: ObservableObject {
        @Published var pressedKeys: Set<UInt16> = []
        @Published var modifierFlags: CGEventFlags = []

        private enum Backend {
            case eventTap(CFMachPort, CFRunLoopSource)
            case localMonitor(Any)
        }

        private var backend: Backend?

        func start() {
            guard backend == nil else { return }

            if installEventTap() {
                return
            }

            installLocalMonitor()
        }

        func stop() {
            switch backend {
            case .eventTap(let tap, let source):
                CGEvent.tapEnable(tap: tap, enable: false)
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            case .localMonitor(let localMonitor):
                NSEvent.removeMonitor(localMonitor)
            case .none:
                break
            }

            backend = nil
            pressedKeys.removeAll()
            modifierFlags = []
        }

        deinit {
            stop()
        }

        func isShortcutActive(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
            let modifiersMatch = requiredModifierFlags(for: shortcut.modifiers).allSatisfy {
                modifierFlags.contains($0)
            }
            let keyMatches = pressedKeys.contains(UInt16(shortcut.carbonKeyCode))
            return modifiersMatch && keyMatches
        }

        private func requiredModifierFlags(for modifiers: NSEvent.ModifierFlags) -> [CGEventFlags] {
            var flags: [CGEventFlags] = []
            if modifiers.contains(.control) { flags.append(.maskControl) }
            if modifiers.contains(.option) { flags.append(.maskAlternate) }
            if modifiers.contains(.shift) { flags.append(.maskShift) }
            if modifiers.contains(.command) { flags.append(.maskCommand) }
            return flags
        }

        private func installEventTap() -> Bool {
            if #available(macOS 10.15, *) {
                guard CGPreflightListenEventAccess() else {
                    return false
                }
            }

            let eventMask: CGEventMask =
                (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)

            guard
                let tap = CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .headInsertEventTap,
                    options: .listenOnly,
                    eventsOfInterest: eventMask,
                    callback: { _, type, event, refcon in
                        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                            return Unmanaged.passUnretained(event)
                        }

                        guard let refcon else {
                            return Unmanaged.passUnretained(event)
                        }

                        let monitor = Unmanaged<OnboardingKeyboardMonitor>
                            .fromOpaque(refcon)
                            .takeUnretainedValue()
                        monitor.handle(type: type, event: event)
                        return Unmanaged.passUnretained(event)
                    },
                    userInfo: Unmanaged.passUnretained(self).toOpaque()
                )
            else {
                return false
            }

            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                CGEvent.tapEnable(tap: tap, enable: false)
                return false
            }

            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            backend = .eventTap(tap, source)
            return true
        }

        private func installLocalMonitor() {
            if let monitor =
                (NSEvent.addLocalMonitorForEvents(
                    matching: [.keyDown, .keyUp, .flagsChanged]
                ) { [weak self] event in
                    self?.handle(event)
                    return event
                })
            {
                backend = .localMonitor(monitor)
            }
        }

        private func handle(_ event: NSEvent) {
            switch event.type {
            case .keyDown:
                if !event.isARepeat {
                    pressedKeys.insert(event.keyCode)
                }
            case .keyUp:
                pressedKeys.remove(event.keyCode)
            case .flagsChanged:
                modifierFlags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            default:
                break
            }
        }

        private func handle(type: CGEventType, event: CGEvent) {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

            switch type {
            case .keyDown:
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    pressedKeys.insert(keyCode)
                }
            case .keyUp:
                pressedKeys.remove(keyCode)
            case .flagsChanged:
                modifierFlags = event.flags
            default:
                break
            }
        }
    }

    // MARK: - Dynamic Shortcut Keycaps

    struct OnboardingShortcutKeySpec: Identifiable, Equatable {
        let id: String
        let symbol: String
        let label: String
        let modifierMask: CGEventFlags?
        let keyCode: UInt16?

        static func specs(for shortcut: KeyboardShortcuts.Shortcut) -> [OnboardingShortcutKeySpec] {
            var items: [OnboardingShortcutKeySpec] = []
            let modifiers = shortcut.modifiers

            if modifiers.contains(.control) {
                items.append(.init(id: "ctrl", symbol: "⌃", label: "control", modifierMask: .maskControl, keyCode: nil))
            }
            if modifiers.contains(.option) {
                items.append(.init(id: "opt", symbol: "⌥", label: "option", modifierMask: .maskAlternate, keyCode: nil))
            }
            if modifiers.contains(.shift) {
                items.append(.init(id: "shift", symbol: "⇧", label: "shift", modifierMask: .maskShift, keyCode: nil))
            }
            if modifiers.contains(.command) {
                items.append(.init(id: "cmd", symbol: "⌘", label: "command", modifierMask: .maskCommand, keyCode: nil))
            }

            let modifierSymbols: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
            let rawDescription = "\(shortcut)"
            let mainSymbol = String(rawDescription.filter { !modifierSymbols.contains($0) })
            let displaySymbol = mainSymbol.isEmpty ? "·" : mainSymbol
            let displayLabel: String
            switch displaySymbol {
            case ".":
                displayLabel = "period"
            case "␣", "Space":
                displayLabel = "space"
            case "↩", "Return":
                displayLabel = "return"
            default:
                displayLabel = displaySymbol.lowercased()
            }

            items.append(
                .init(
                    id: "key-\(shortcut.carbonKeyCode)",
                    symbol: displaySymbol == "Space" ? "␣" : displaySymbol,
                    label: displayLabel,
                    modifierMask: nil,
                    keyCode: UInt16(shortcut.carbonKeyCode)
                )
            )
            return items
        }

        static func formattedString(for shortcut: KeyboardShortcuts.Shortcut?) -> String {
            guard let shortcut else {
                return String(localized: "Not set")
            }
            return specs(for: shortcut)
                .map { $0.symbol == "␣" ? "Space" : $0.symbol }
                .joined(separator: " ")
        }
    }

    struct OnboardingShortcutKeycapsView: View {
        let shortcut: KeyboardShortcuts.Shortcut?
        @ObservedObject var monitor: OnboardingKeyboardMonitor

        var body: some View {
            if let shortcut {
                let specs = OnboardingShortcutKeySpec.specs(for: shortcut)
                HStack(spacing: 10) {
                    ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
                        if index > 0 {
                            Text("+")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                        }

                        OnboardingKeyCap(
                            symbol: spec.symbol,
                            label: spec.label,
                            isPressed: isKeyPressed(spec)
                        )
                    }
                }
            } else {
                Text("No shortcut configured")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacUI.Foreground.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(MacUI.LinearSurfaces.elevated)
                    )
            }
        }

        private func isKeyPressed(_ spec: OnboardingShortcutKeySpec) -> Bool {
            if let mask = spec.modifierMask {
                return monitor.modifierFlags.contains(mask)
            }
            if let keyCode = spec.keyCode {
                return monitor.pressedKeys.contains(keyCode)
            }
            return false
        }
    }

    private struct OnboardingKeyCap: View {
        let symbol: String
        let label: String
        let isPressed: Bool

        var body: some View {
            VStack(spacing: 3) {
                Text(symbol)
                    .font(.system(size: 18, weight: .medium))
                    .lineLimit(1)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.65)
                    .lineLimit(1)
            }
            .foregroundStyle(
                isPressed ? OnboardingPalette.primaryButtonForeground : MacUI.Foreground.primary
            )
            .padding(.horizontal, 16)
            .frame(minWidth: 68, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isPressed
                            ? LinearGradient(
                                colors: [
                                    OnboardingPalette.primaryButtonBackground,
                                    OnboardingPalette.primaryButtonBackground,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : LinearGradient(
                                colors: [OnboardingPalette.keycapTop, OnboardingPalette.keycapBottom],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isPressed ? Color.clear : MacUI.LinearSurfaces.hairlineStrong,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(isPressed ? 0 : 0.08),
                radius: isPressed ? 0 : 4,
                x: 0,
                y: isPressed ? 0 : 2
            )
            .scaleEffect(isPressed ? 0.965 : 1)
            .offset(y: isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
        }
    }

    struct OnboardingCompactHotkeyBadge: View {
        let shortcut: KeyboardShortcuts.Shortcut?

        var body: some View {
            Text(verbatim: OnboardingShortcutKeySpec.formattedString(for: shortcut))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(MacUI.Foreground.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MacUI.LinearSurfaces.elevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(MacUI.LinearSurfaces.hairlineStrong, lineWidth: 1)
                )
        }
    }
#endif
