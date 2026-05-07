import Cocoa
import SwiftUI

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let store: RegisterStore
    private let clipboard: ClipboardHelper
    private let historyStore: ClipboardHistoryStore

    private var popoverVM: RegistersVM!
    private var panelWindow: NSWindow?

    init(
        store: RegisterStore,
        clipboard: ClipboardHelper,
        historyStore: ClipboardHistoryStore
    ) {
        self.store = store
        self.clipboard = clipboard
        self.historyStore = historyStore

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⌘#"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleCenteredPanel)

        popoverVM = RegistersVM(store: store)
        let historyVM = HistoryVM(historyStore: historyStore, registerStore: store)

        let root = TabView {
            RegistersPopover(vm: popoverVM)
                .tabItem { Label("Registers", systemImage: "number") }

            HistoryTab(vm: historyVM)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .padding(.top, 4)

        let host = NSHostingController(rootView: root)
        let panel = NSWindow(contentViewController: host)
        panel.title = "Alto"
        panel.setContentSize(NSSize(width: 620, height: 500))
        panel.styleMask = [.titled, .closable, .miniaturizable]
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.center()
        self.panelWindow = panel
    }

    @objc func toggleCenteredPanel() {
        guard let panelWindow else { return }
        if panelWindow.isVisible {
            panelWindow.orderOut(nil)
        } else {
            popoverVM.refresh()
            panelWindow.center()
            NSApp.activate(ignoringOtherApps: true)
            panelWindow.makeKeyAndOrderFront(nil)
            panelWindow.orderFrontRegardless()
        }
    }

    func reloadMenu() {
        popoverVM?.refresh()
    }
}
