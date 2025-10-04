import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusBarController!
    private var registers = RegisterStore()
    private var hotkeys: HotkeyManager!
    private var clipboard = ClipboardHelper()
    private var historyStore = ClipboardHistoryStore()
    private var settings = SettingsStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        registers.load()
        historyStore.load()

        status = StatusBarController(store: registers,
                                     clipboard: clipboard,
                                     historyStore: historyStore,
                                     settings: settings)

        hotkeys = HotkeyManager(settings: settings)

        // PASTE
        hotkeys.onPaste = { [weak self] n in
            guard let self, (1...9).contains(n) else { return }
            self.clipboard.pasteText(self.registers[n])
            HUD.shared.show("Pasted → reg \(n)")
        }

        // SAVE
        hotkeys.onSave = { [weak self] n in
            guard let self, (1...9).contains(n) else { return }
            self.clipboard.captureSelection { text, changed in
                if !changed { HUD.shared.show("No selection; saved clipboard → reg \(n)") }
                self.registers[n] = text
                self.registers.save()
                self.status.reloadMenu()
                self.historyStore.add(text: text) // record only on save
                HUD.shared.show("Saved → reg \(n)")
            }
        }

        // CLEAR ALL
        hotkeys.onClearAll = { [weak self] in
            guard let self else { return }
            self.registers.clearAll()
            self.status.reloadMenu()
            HUD.shared.show("All registers cleared")
        }

        // Install with current settings; future changes auto-reinstall via NotificationCenter
        hotkeys.install()

        HUD.shared.show("Ready")
    }
}
