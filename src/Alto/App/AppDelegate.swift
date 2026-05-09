import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusBarController!
    private var registers = RegisterStore()
    private var hotkeys: HotkeyManager!
    private var clipboard = ClipboardHelper()
    private var historyStore = ClipboardHistoryStore()
    private var stagedPayload: PayloadMap?
    private var stagedCopyReady = false
    private var stagedCopyInFlight = false
    private var queuedSaveRegister: Int?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
            self.clipboard.pastePayload(self.registers[n])
            HUD.shared.show("Pasted -> reg \(n)")
        }

        hotkeys.onSave = { [weak self] n in
            guard let self, (1...9).contains(n) else { return }
            if self.stagedCopyInFlight {
                self.queuedSaveRegister = n
                return
            }

            if self.stagedCopyReady,
               let payload = self.stagedPayload,
               !ClipboardPayload.isEmpty(payload)
            {
                self.storePayloadToRegister(payload, register: n)
                self.clearStagedCopy()
                return
            }

            self.clipboard.captureSelection { payload, succeeded in
                if !succeeded {
                    HUD.shared.show("Copy failed (check Accessibility permission)")
                    return
                }
                self.storePayloadToRegister(payload, register: n)
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
            self.registers[n] = ClipboardPayload.empty()
            self.registers.save()
            self.status.reloadMenu()
            HUD.shared.show("Cleared reg \(n)")
        }

        hotkeys.onTogglePanel = { [weak self] in
            self?.status.toggleCenteredPanel()
        }

        hotkeys.onPreview = { [weak self] n in
            guard let self, (1...9).contains(n) else { return }
            RegisterPreviewController.shared.showFromHotkey(
                payload: self.registers[n],
                registerIndex: n
            )
        }

        hotkeys.onSwap = { [weak self] a, b in
            guard let self, (1...9).contains(a), (1...9).contains(b) else { return }
            self.registers.swapRegisters(a, b)
            self.status.reloadMenu()
            HUD.shared.show("Swapped reg \(a) <-> reg \(b)")
        }

        hotkeys.install()
        HUD.shared.show("Ready")
    }

    private func prepareStagedCopy() {
        clearStagedCopy()
        stagedCopyInFlight = true
        clipboard.captureSelection { [weak self] payload, succeeded in
            guard let self else { return }
            self.stagedCopyInFlight = false
            if succeeded, !ClipboardPayload.isEmpty(payload) {
                self.stagedPayload = payload
                self.stagedCopyReady = true
            }

            if let register = self.queuedSaveRegister {
                self.queuedSaveRegister = nil
                if self.stagedCopyReady,
                   let staged = self.stagedPayload,
                   !ClipboardPayload.isEmpty(staged)
                {
                    self.storePayloadToRegister(staged, register: register)
                    self.clearStagedCopy()
                } else {
                    HUD.shared.show("Copy failed (check Accessibility permission)")
                }
            }
        }
    }

    private func clearStagedCopy() {
        stagedPayload = nil
        stagedCopyReady = false
        stagedCopyInFlight = false
        queuedSaveRegister = nil
    }

    private func storePayloadToRegister(_ payload: PayloadMap, register n: Int) {
        let kind = ClipboardPayload.dominantKind(payload)
        registers[n] = payload
        registers.save()
        status.reloadMenu()
        historyStore.add(payload: payload)
        HUD.shared.show("Saved \(ClipboardPayload.hudLabel(for: kind)) -> reg \(n)")
    }
}
