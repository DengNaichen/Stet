//#if os(macOS)
//import AppKit
//import ApplicationServices
//import Carbon
//import os

//private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet", category: "hotkey")

//private let hotkeySignature = OSType(0x41525459) // ARTY
//
//private let carbonHotkeyHandler: EventHandlerUPP = { _, event, userData in
//    guard let userData, let event else { return noErr }
//
//    let service = Unmanaged<AdaptiveGlobalHotkeyService>
//        .fromOpaque(userData)
//        .takeUnretainedValue()
//
//    var hotKeyID = EventHotKeyID()
//    let status = GetEventParameter(
//        event,
//        EventParamName(kEventParamDirectObject),
//        EventParamType(typeEventHotKeyID),
//        nil,
//        MemoryLayout<EventHotKeyID>.size,
//        nil,
//        &hotKeyID
//    )
//
//    guard status == noErr,
//          hotKeyID.signature == hotkeySignature,
//          service.matchesCarbonHotKeyID(hotKeyID.id) else {
//        return noErr
//    }
//
//    let eventKind = GetEventKind(event)
//
//    Task { @MainActor in
//        switch eventKind {
//        case UInt32(kEventHotKeyPressed):
//            service.handleKeyDown()
//        case UInt32(kEventHotKeyReleased):
//            service.handleKeyUp()
//        default:
//            break
//        }
//    }
//
//    return noErr
//}
//
//@MainActor
//protocol GlobalHotkeyService: AnyObject {
//    var displayString: String { get }
//    var isRegistered: Bool { get }
//    var currentShortcut: GlobalHotkeyShortcut? { get }
//    func start(
//        onKeyDown: @escaping @MainActor () -> Void,
//        onKeyUp: @escaping @MainActor () -> Void
//    )
//    @discardableResult
//    func updateShortcut(_ shortcut: GlobalHotkeyShortcut) -> Bool
//    func clearShortcut()
//}
//
//@MainActor
//final class AdaptiveGlobalHotkeyService: GlobalHotkeyService {
//    private enum Backend {
//        case carbon(EventHotKeyRef)
//        case eventTap(CFMachPort, CFRunLoopSource)
//    }
//
//    private var backend: Backend?
//    private var eventHandlerRef: EventHandlerRef?
//    private let hotKeyID: UInt32
//    private var preferredShortcut: GlobalHotkeyShortcut?
//    private(set) var currentShortcut: GlobalHotkeyShortcut?
//    private var keyDownHandler: (@MainActor () -> Void)?
//    private var keyUpHandler: (@MainActor () -> Void)?
//    private var isPressActive = false
//    private var activeSidedModifiers: SidedModifierFlags = []
//
//    init(
//        preferredShortcut: GlobalHotkeyShortcut? = .defaultShortcut,
//        hotKeyID: UInt32 = 1
//    ) {
//        self.preferredShortcut = preferredShortcut
//        self.hotKeyID = hotKeyID
//    }
//
//    var displayString: String {
//        currentShortcut?.displayString ?? preferredShortcut?.displayString ?? "Unassigned"
//    }
//
//    var isRegistered: Bool {
//        backend != nil
//    }
//
//    func start(
//        onKeyDown: @escaping @MainActor () -> Void,
//        onKeyUp: @escaping @MainActor () -> Void
//    ) {
//        keyDownHandler = onKeyDown
//        keyUpHandler = onKeyUp
//
//        if eventHandlerRef == nil {
//            installCarbonEventHandler()
//        }
//
//        if backend == nil, preferredShortcut != nil {
//            _ = registerPreferredShortcut(allowFallback: true)
//        }
//    }
//
//    @discardableResult
//    func updateShortcut(_ shortcut: GlobalHotkeyShortcut) -> Bool {
//        let previousPreferredShortcut = preferredShortcut
//        let previousCurrentShortcut = currentShortcut
//
//        preferredShortcut = shortcut
//        unregisterBackend()
//
//        if registerPreferredShortcut(allowFallback: false) {
//            logger.info("Updated hotkey to \(shortcut.displayString)")
//            return true
//        }
//
//        preferredShortcut = previousPreferredShortcut
//        unregisterBackend()
//
//        if let previousCurrentShortcut {
//            _ = registerSpecificShortcut(previousCurrentShortcut)
//        } else {
//            _ = registerPreferredShortcut(allowFallback: true)
//        }
//
//        return false
//    }
//
//    func clearShortcut() {
//        unregisterBackend()
//        preferredShortcut = nil
//    }
//
//    func handleKeyDown() {
//        guard !isPressActive else { return }
//        isPressActive = true
//        logger.info("Hotkey key-down")
//        keyDownHandler?()
//    }
//
//    func handleKeyUp() {
//        guard isPressActive else { return }
//        isPressActive = false
//        logger.info("Hotkey key-up")
//        keyUpHandler?()
//    }
//
//    deinit {
//        switch backend {
//        case .carbon(let hotKeyRef):
//            UnregisterEventHotKey(hotKeyRef)
//        case .eventTap(let tap, let source):
//            CGEvent.tapEnable(tap: tap, enable: false)
//            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
//        case .none:
//            break
//        }
//        if let eventHandlerRef {
//            RemoveEventHandler(eventHandlerRef)
//        }
//    }
//
//    private func installCarbonEventHandler() {
//        var eventTypes = [
//            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
//            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
//        ]
//
//        InstallEventHandler(
//            GetApplicationEventTarget(),
//            carbonHotkeyHandler,
//            eventTypes.count,
//            &eventTypes,
//            Unmanaged.passUnretained(self).toOpaque(),
//            &eventHandlerRef
//        )
//    }
//
//    fileprivate func matchesCarbonHotKeyID(_ hotKeyID: UInt32) -> Bool {
//        self.hotKeyID == hotKeyID
//    }
//
//    private func registerPreferredShortcut(allowFallback: Bool) -> Bool {
//        guard let preferredShortcut else { return false }
//
//        let candidates = [preferredShortcut] + (allowFallback
//            ? GlobalHotkeyShortcut.fallbackShortcuts.filter { $0 != preferredShortcut }
//            : [])
//
//        for shortcut in candidates {
//            if registerSpecificShortcut(shortcut) {
//                return true
//            }
//        }
//
//        return false
//    }
//
//    private func registerSpecificShortcut(_ shortcut: GlobalHotkeyShortcut) -> Bool {
//        if shortcut.requiresEventTap {
//            return installEventTap(for: shortcut)
//        }
//
//        return registerCarbonHotkey(shortcut)
//    }
//
//    private func registerCarbonHotkey(_ shortcut: GlobalHotkeyShortcut) -> Bool {
//        var newHotKeyRef: EventHotKeyRef?
//        let hotKeyID = EventHotKeyID(signature: hotkeySignature, id: self.hotKeyID)
//        let status = RegisterEventHotKey(
//            UInt32(shortcut.keyCode),
//            shortcut.carbonModifiers,
//            hotKeyID,
//            GetApplicationEventTarget(),
//            0,
//            &newHotKeyRef
//        )
//
//        guard status == noErr, let newHotKeyRef else {
//            logger.warning("Failed to register Carbon hotkey \(shortcut.displayString)")
//            return false
//        }
//
//        backend = .carbon(newHotKeyRef)
//        currentShortcut = shortcut
//        return true
//    }
//
//    private func installEventTap(for shortcut: GlobalHotkeyShortcut) -> Bool {
//        let inputMonitoringGranted: Bool
//        if #available(macOS 10.15, *) {
//            inputMonitoringGranted = CGPreflightListenEventAccess()
//        } else {
//            inputMonitoringGranted = true
//        }
//
//        guard inputMonitoringGranted else {
//            logger.warning(
//                "Input Monitoring is required for hotkey \(shortcut.displayString)"
//            )
//            return false
//        }
//
//        let eventMask: CGEventMask =
//            (1 << CGEventType.keyDown.rawValue) |
//            (1 << CGEventType.keyUp.rawValue) |
//            (1 << CGEventType.flagsChanged.rawValue)
//
//        guard let tap = CGEvent.tapCreate(
//            tap: .cgSessionEventTap,
//            place: .tailAppendEventTap,
//            options: .listenOnly,
//            eventsOfInterest: eventMask,
//            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
//                guard let refcon else { return Unmanaged.passUnretained(event) }
//                let service = Unmanaged<AdaptiveGlobalHotkeyService>.fromOpaque(refcon).takeUnretainedValue()
//                service.handleEventTap(type: type, event: event)
//                return Unmanaged.passUnretained(event)
//            },
//            userInfo: Unmanaged.passUnretained(self).toOpaque()
//        ) else {
//            logger.error("Failed to create event tap for \(shortcut.displayString)")
//            return false
//        }
//
//        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
//            CGEvent.tapEnable(tap: tap, enable: false)
//            return false
//        }
//        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
//        CGEvent.tapEnable(tap: tap, enable: true)
//
//        backend = .eventTap(tap, source)
//        currentShortcut = shortcut
//        return true
//    }
//
//    private func handleEventTap(type: CGEventType, event: CGEvent) {
//        guard case let .eventTap(tap, _) = backend,
//              let shortcut = currentShortcut else {
//            return
//        }
//
//        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
//            CGEvent.tapEnable(tap: tap, enable: true)
//            return
//        }
//
//        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
//        let flags = event.flags.intersection(GlobalHotkeyShortcut.cgFlags(from: .hotkeyRelevant))
//        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
//
//        if type == .flagsChanged,
//           SidedModifierFlags.sidedFlag(for: keyCode) != nil {
//            activeSidedModifiers = SidedModifierFlags.toggled(from: activeSidedModifiers, keyCode: keyCode)
//            activeSidedModifiers = activeSidedModifiers.filtered(
//                by: GlobalHotkeyShortcut.modifierFlags(from: flags)
//            )
//        }
//
//        if shortcut.isModifierOnly {
//            guard type == .flagsChanged else { return }
//
//            let comboIsDown = shortcut.matches(
//                eventFlags: flags,
//                activeSidedModifiers: activeSidedModifiers
//            )
//            let fnOnlyPressed = shortcut.modifiers == [.function] && keyCode == UInt16(kVK_Function)
//            let triggerDown = comboIsDown || fnOnlyPressed
//
//            if triggerDown && !isPressActive {
//                handleKeyDown()
//            } else if !comboIsDown && isPressActive {
//                handleKeyUp()
//            }
//
//            return
//        }
//
//        let flagsMatch = shortcut.matches(
//            eventFlags: flags,
//            activeSidedModifiers: activeSidedModifiers
//        )
//
//        switch type {
//        case .keyDown:
//            guard keyCode == shortcut.keyCode, flagsMatch, !isAutoRepeat else { return }
//            handleKeyDown()
//        case .keyUp:
//            guard keyCode == shortcut.keyCode else { return }
//            handleKeyUp()
//        default:
//            break
//        }
//    }
//
//    private func unregisterBackend() {
//        switch backend {
//        case .carbon(let hotKeyRef):
//            UnregisterEventHotKey(hotKeyRef)
//        case .eventTap(let tap, let source):
//            CGEvent.tapEnable(tap: tap, enable: false)
//            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
//        case .none:
//            break
//        }
//
//        backend = nil
//        currentShortcut = nil
//        isPressActive = false
//        activeSidedModifiers = []
//    }
//}
//#endif
