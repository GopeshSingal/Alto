import Cocoa
import Carbon

final class HotkeyManager {
    // Callbacks wired by AppDelegate
    var onPaste: ((Int) -> Void)?
    var onSave: ((Int) -> Void)?
    var onClearAll: (() -> Void)?

    private var hotkeys: [EventHotKeyRef?] = []
    private let box = HotkeyBox()

    // Settings-driven modifier masks
    private let settings: SettingsStore

    // Correct keycodes for digits 0..9 (US ANSI)
    private let digitKC: [Int] = [
        kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
        kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
    ]

    init(settings: SettingsStore) {
        self.settings = settings

        // Install handler once
        if !box.handlerInstalled {
            var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(),
                                hotKeyHandler,
                                1, &eventSpec,
                                Unmanaged.passUnretained(box).toOpaque(),
                                nil)
            box.handlerInstalled = true
        }

        // React to settings changes: re-register hotkeys
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reinstall),
                                               name: .KRSettingsChanged,
                                               object: nil)
    }

    // Install (or reinstall) all hotkeys with current modifiers
    @objc func install() {
        unregisterAll()
        box.actions.removeAll()

        let pasteMods = settings.pasteMask
        let saveMods  = settings.saveMask

        // Clear all (register 0) uses the Paste modifiers + 0
        register(keyCode: digitKC[0], modifiers: pasteMods, id: 1000) { [weak self] in
            self?.onClearAll?()
        }

        // 1..9 paste / save
        for n in 1...9 {
            register(keyCode: digitKC[n], modifiers: pasteMods, id: UInt32(10 + n)) { [weak self] in
                self?.onPaste?(n)
            }
            register(keyCode: digitKC[n], modifiers: saveMods, id: UInt32(110 + n)) { [weak self] in
                self?.onSave?(n)
            }
        }
    }

    @objc private func reinstall() {
        install()
    }

    // MARK: - Registration helpers

    private func register(keyCode: Int, modifiers: UInt32, id: UInt32, action: @escaping () -> Void) {
        var ref: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(signature: OSType("KReg".fourCC), id: id)

        box.actions[id] = action

        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            NSLog("[KR] RegisterEventHotKey failed id \(id) status \(status)")
        }
        hotkeys.append(ref)
    }

    private func unregisterAll() {
        for hk in hotkeys { if let hk { UnregisterEventHotKey(hk) } }
        hotkeys.removeAll()
    }
}

// MARK: - Box & Handler

private final class HotkeyBox {
    var actions: [UInt32: () -> Void] = [:]
    var handlerInstalled = false
    func invoke(_ id: UInt32) { actions[id]?() }
}

private func hotKeyHandler(_ nextHandler: EventHandlerCallRef?,
                           _ event: EventRef?,
                           _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return noErr }
    var hkID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                      EventParamType(typeEventHotKeyID), nil,
                      MemoryLayout<EventHotKeyID>.size, nil, &hkID)
    let box = Unmanaged<HotkeyBox>.fromOpaque(userData).takeUnretainedValue()
    box.invoke(hkID.id)
    return noErr
}

private extension String {
    var fourCC: UInt32 { utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
}
