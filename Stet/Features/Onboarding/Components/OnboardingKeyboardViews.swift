#if os(macOS)
    import Combine
    import ApplicationServices
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

    struct OnboardingKeyboardView: View {
        @StateObject private var keyboardMonitor = OnboardingKeyboardMonitor()
        @State private var hintStep = 0
        private let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

        var body: some View {
            VStack(spacing: 30) {
                VStack(alignment: .trailing, spacing: 12) {
                    HStack(spacing: 10) {
                        KeyCap(
                            text: "N", subtext: nil, icon: nil, width: 50,
                            isPressed: keyboardMonitor.pressedKeys.contains(45))
                        KeyCap(
                            text: "M", subtext: nil, icon: nil, width: 50,
                            isPressed: keyboardMonitor.pressedKeys.contains(46))
                        KeyCap(
                            text: ",", subtext: nil, icon: nil, width: 50,
                            isPressed: keyboardMonitor.pressedKeys.contains(43))
                        KeyCap(
                            text: ".", subtext: nil, icon: nil, width: 50,
                            isPressed: keyboardMonitor.pressedKeys.contains(47),
                            isHinted: hintStep == 2 || hintStep == 3
                        )
                        KeyCap(
                            text: "/", subtext: "?", icon: nil, width: 50,
                            isPressed: keyboardMonitor.pressedKeys.contains(44))
                        KeyCap(
                            text: "⇧", subtext: nil, icon: nil, width: 90,
                            isPressed: keyboardMonitor.modifierFlags.contains(.maskShift))
                    }

                    HStack(alignment: .bottom, spacing: 10) {
                        KeyCap(
                            text: "space", subtext: nil, icon: nil, width: 130,
                            isPressed: keyboardMonitor.pressedKeys.contains(49))
                        KeyCap(
                            text: "command", subtext: "⌘", icon: nil, width: 70,
                            isPressed: keyboardMonitor.modifierFlags.contains(.maskCommand),
                            isHinted: hintStep == 1 || hintStep == 2 || hintStep == 3
                        )
                        KeyCap(
                            text: "option", subtext: "⌥", icon: nil, width: 60,
                            isPressed: keyboardMonitor.modifierFlags.contains(.maskAlternate))

                        HStack(alignment: .bottom, spacing: 4) {
                            KeyCap(
                                text: "", subtext: nil, icon: "chevron.left", width: 44, height: 23,
                                isPressed: keyboardMonitor.pressedKeys.contains(123))

                            VStack(spacing: 4) {
                                KeyCap(
                                    text: "", subtext: nil, icon: "chevron.up", width: 44,
                                    height: 23, isPressed: keyboardMonitor.pressedKeys.contains(126)
                                )
                                KeyCap(
                                    text: "", subtext: nil, icon: "chevron.down", width: 44,
                                    height: 23, isPressed: keyboardMonitor.pressedKeys.contains(125)
                                )
                            }

                            KeyCap(
                                text: "", subtext: nil, icon: "chevron.right", width: 44,
                                height: 23, isPressed: keyboardMonitor.pressedKeys.contains(124))
                        }
                    }
                }

                Text("When pressed, do you see the button turn black?")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .onReceive(timer) { _ in
                // Animation sequence:
                // 0: All up
                // 1: Command down
                // 2: Command + Dot down
                // 3: Command + Dot down (staying)
                // 4: All up
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    hintStep = (hintStep + 1) % 5
                }
            }
            .onAppear {
                keyboardMonitor.start()
            }
            .onDisappear {
                keyboardMonitor.stop()
            }
        }
    }

    private struct KeyCap: View {
        let text: String
        let subtext: String?
        let icon: String?
        let width: CGFloat
        var height: CGFloat = 50
        let isPressed: Bool
        var isHinted: Bool = false

        var body: some View {
            VStack(spacing: 2) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .frame(maxWidth: .infinity, alignment: text.isEmpty ? .center : .leading)
                        .padding(.leading, text.isEmpty ? 0 : 6)
                        .padding(.top, 4)
                }

                if let subtext {
                    Text(subtext)
                        .font(.system(size: 10))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)

                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 13, weight: .regular))
                        .frame(
                            maxWidth: .infinity,
                            alignment: icon != nil && !text.isEmpty ? .leading : .center
                        )
                        .padding(.leading, icon != nil && !text.isEmpty ? 6 : 0)
                        .padding(.bottom, 6)
                }
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPressed || isHinted ? Color.black : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isPressed || isHinted ? Color.clear : Color.black.opacity(0.1), lineWidth: 1)
            )
            .foregroundStyle(isPressed || isHinted ? Color.white : Color.black.opacity(0.6))
            .shadow(color: Color.black.opacity(isPressed || isHinted ? 0 : 0.05), radius: 2, x: 0, y: 1)
            .animation(.easeInOut(duration: 0.2), value: isPressed || isHinted)
        }
    }

    struct OnboardingHotkeyDisplay: View {
        @StateObject private var keyboardMonitor = OnboardingKeyboardMonitor()

        var body: some View {
            VStack(spacing: 12) {
                Text("Press your hotkey")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    KeyCap(
                        text: "command", subtext: "⌘", icon: nil, width: 80,
                        isPressed: keyboardMonitor.modifierFlags.contains(.maskCommand))

                    Text("+")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)

                    KeyCap(
                        text: ".", subtext: nil, icon: nil, width: 50,
                        isPressed: keyboardMonitor.pressedKeys.contains(47))
                }
            }
            .onAppear {
                keyboardMonitor.start()
            }
            .onDisappear {
                keyboardMonitor.stop()
            }
        }
    }
#endif
