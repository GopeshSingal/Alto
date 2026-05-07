import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusBarController!
    private var registers = RegisterStore()
    private var hotkeys: HotkeyManager!
    private var clipboard = ClipboardHelper()
    private var historyStore = ClipboardHistoryStore()
    private var stagedCopyText: String?
    private var stagedCopyReady = false
    private var stagedCopyInFlight = false
    private var queuedSaveRegister: Int?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registers.load()
        historyStore.load()

        status = StatusBarController(
            store: registers,
            clipboard: clipboard,
            historyStore: historyStore
        )

        hotkeys = HotkeyManager()

        hotkeys.onPaste = { [weak self] n in
            guard let self, (1...9).contains(n) else { return }
            self.clipboard.pasteText(self.registers[n])
            HUD.shared.show("Pasted -> reg \(n)")
        }

        hotkeys.onSave = { [weak self] n in
            guard let self, (1...9).contains(n) else { return }
            if self.stagedCopyInFlight {
                self.queuedSaveRegister = n
                return
            }

            if self.stagedCopyReady, let text = self.stagedCopyText, !text.isEmpty {
                self.storeTextToRegister(text, register: n)
                self.clearStagedCopy()
                return
            }

            self.clipboard.captureSelection { text, changed in
                if !changed {
                    HUD.shared.show("Copy failed (check Accessibility permission)")
                    return
                }
                self.storeTextToRegister(text, register: n)
            }
        }

        hotkeys.onCopyModeEntered = { [weak self] in
            self?.prepareStagedCopy()
        }

        hotkeys.onClearAll = { [weak self] in
            guard let self else { return }
            self.registers.clearAll()
            self.status.reloadMenu()
            HUD.shared.show("All registers cleared")
        }

        hotkeys.onClear = { [weak self] n in
            guard let self, (1...9).contains(n) else { return }
            self.registers[n] = ""
            self.registers.save()
            self.status.reloadMenu()
            HUD.shared.show("Cleared reg \(n)")
        }

        hotkeys.onTogglePanel = { [weak self] in
            self?.status.toggleCenteredPanel()
        }

        hotkeys.install()
        HUD.shared.show("Ready")
    }

    private func prepareStagedCopy() {
        clearStagedCopy()
        stagedCopyInFlight = true
        clipboard.captureSelection { [weak self] text, changed in
            guard let self else { return }
            self.stagedCopyInFlight = false
            if changed && !text.isEmpty {
                self.stagedCopyText = text
                self.stagedCopyReady = true
            }

            if let register = self.queuedSaveRegister {
                self.queuedSaveRegister = nil
                if self.stagedCopyReady, let staged = self.stagedCopyText, !staged.isEmpty {
                    self.storeTextToRegister(staged, register: register)
                    self.clearStagedCopy()
                } else {
                    HUD.shared.show("Copy failed (check Accessibility permission)")
                }
            }
        }
    }

    private func clearStagedCopy() {
        stagedCopyText = nil
        stagedCopyReady = false
        stagedCopyInFlight = false
        queuedSaveRegister = nil
    }

    private func storeTextToRegister(_ text: String, register n: Int) {
        registers[n] = text
        registers.save()
        status.reloadMenu()
        historyStore.add(text: text)
        HUD.shared.show("Saved -> reg \(n)")
    }
}
