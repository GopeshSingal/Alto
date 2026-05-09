import Cocoa
import Carbon

final class HotkeyManager {
    var onPaste: ((Int) -> Void)?
    var onSave: ((Int) -> Void)?
    var onClear: ((Int) -> Void)?
    var onCopyModeEntered: (() -> Void)?
    var onClearAll: (() -> Void)?
    var onTogglePanel: (() -> Void)?
    var onPreview: ((Int) -> Void)?

    private var hotkeys: [EventHotKeyRef?] = []
    private let box = HotkeyBox()
    private var prefixTimeout: DispatchWorkItem?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private let prefixKeyCode = kVK_ANSI_A
    private let prefixTimeoutSeconds: TimeInterval = 2.5
    private var prefixMode: PrefixMode = .idle

    private let digitKC: [Int] = [
        kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
        kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
    ]

    init() {
        if !box.handlerInstalled {
            var eventSpec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            InstallEventHandler(
                GetApplicationEventTarget(),
                hotKeyHandler,
                1,
                &eventSpec,
                Unmanaged.passUnretained(box).toOpaque(),
                nil
            )
            box.handlerInstalled = true
        }
    }

    func install() {
        unregisterAll()
        box.actions.removeAll()
        resetPrefixState()

        // TMUX-style prefix key: Ctrl + A
        register(
            keyCode: prefixKeyCode,
            modifiers: UInt32(controlKey),
            id: 3000
        ) { [weak self] in
            self?.handlePrefixPressed()
        }
    }

    private func register(keyCode: Int, modifiers: UInt32, id: UInt32, action: @escaping () -> Void) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType("KReg".fourCC), id: id)
        box.actions[id] = action

        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status != noErr {
            NSLog("[KR] RegisterEventHotKey failed id \(id) status \(status)")
        }
        hotkeys.append(ref)
    }

    private func handlePrefixPressed() {
        prefixMode = .awaitingCommand
        installKeyMonitors()
        schedulePrefixTimeout()
    }

    private func installKeyMonitors() {
        removeKeyMonitors()

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    private func removeKeyMonitors() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard prefixMode != .idle else { return }

        // Ignore synthetic Cmd+C used internally during staged capture.
        if event.modifierFlags.contains(.command) {
            return
        }

        // Require Ctrl to remain held for the full sequence.
        if !event.modifierFlags.contains(.control) {
            if event.keyCode == UInt16(kVK_Escape) {
                resetPrefixState()
                return
            }
            resetPrefixState()
            return
        }

        if event.modifierFlags.contains(.control), event.keyCode == UInt16(prefixKeyCode) {
            schedulePrefixTimeout()
            return
        }

        if prefixMode == .awaitingCommand, isCopyCommand(event) {
            prefixMode = .awaitingCopyRegister
            onCopyModeEntered?()
            schedulePrefixTimeout()
            return
        }

        if prefixMode == .awaitingCommand, isMenuCommand(event) {
            onTogglePanel?()
            resetPrefixState()
            return
        }

        if prefixMode == .awaitingCommand, isDeleteCommand(event) {
            prefixMode = .awaitingDeleteRegister
            schedulePrefixTimeout()
            return
        }

        if prefixMode == .awaitingCommand, isPreviewCommand(event) {
            prefixMode = .awaitingPreviewRegister
            schedulePrefixTimeout()
            return
        }

        if let register = registerForKeyEvent(event) {
            switch prefixMode {
            case .awaitingCopyRegister:
                if (1...9).contains(register) {
                    onSave?(register)
                }
            case .awaitingDeleteRegister:
                if register == 0 {
                    onClearAll?()
                } else if (1...9).contains(register) {
                    onClear?(register)
                }
            case .awaitingPreviewRegister:
                if (1...9).contains(register) {
                    onPreview?(register)
                }
            case .awaitingCommand:
                if (1...9).contains(register) {
                    onPaste?(register)
                }
            case .idle:
                break
            }
            resetPrefixState()
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            resetPrefixState()
        }
    }

    private func isCopyCommand(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased()
        return key == "c" || event.keyCode == UInt16(kVK_ANSI_C)
    }

    private func isMenuCommand(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased()
        return key == "m" || event.keyCode == UInt16(kVK_ANSI_M)
    }

    private func isDeleteCommand(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased()
        return key == "d" || event.keyCode == UInt16(kVK_ANSI_D)
    }

    private func isPreviewCommand(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased()
        return key == "v" || event.keyCode == UInt16(kVK_ANSI_V)
    }

    private func registerForKeyEvent(_ event: NSEvent) -> Int? {
        if let chars = event.charactersIgnoringModifiers,
           chars.count == 1,
           let scalar = chars.unicodeScalars.first,
           CharacterSet.decimalDigits.contains(scalar),
           let value = Int(chars),
           (0...9).contains(value) {
            return value
        }

        let keyCode = event.keyCode
        for n in 0...9 where UInt16(digitKC[n]) == keyCode {
            return n
        }
        return nil
    }

    private func schedulePrefixTimeout() {
        cancelPrefixTimeout()
        let work = DispatchWorkItem { [weak self] in
            self?.resetPrefixState()
        }
        prefixTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + prefixTimeoutSeconds, execute: work)
    }

    private func cancelPrefixTimeout() {
        prefixTimeout?.cancel()
        prefixTimeout = nil
    }

    private func resetPrefixState() {
        cancelPrefixTimeout()
        prefixMode = .idle
        removeKeyMonitors()
    }

    private func unregisterAll() {
        for hk in hotkeys {
            if let hk {
                UnregisterEventHotKey(hk)
            }
        }
        hotkeys.removeAll()
    }
}

private enum PrefixMode {
    case idle
    case awaitingCommand
    case awaitingCopyRegister
    case awaitingDeleteRegister
    case awaitingPreviewRegister
}

private final class HotkeyBox {
    var actions: [UInt32: () -> Void] = [:]
    var handlerInstalled = false

    func invoke(_ id: UInt32) {
        actions[id]?()
    }
}

private func hotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    var hkID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )
    let box = Unmanaged<HotkeyBox>.fromOpaque(userData).takeUnretainedValue()
    box.invoke(hkID.id)
    return noErr
}

private extension String {
    var fourCC: UInt32 {
        utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
