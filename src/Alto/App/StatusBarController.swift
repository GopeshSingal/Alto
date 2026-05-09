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
        let historyVM = HistoryVM(historyStore: historyStore, registerStore: store) { [weak self] in
            self?.popoverVM.refresh()
        }

        let root = TabView {
            RegistersPopover(vm: popoverVM)
                .tabItem { Label("Registers", systemImage: "number") }

            HistoryTab(vm: historyVM)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .padding(.top, 4)

        let host = NSHostingController(rootView: root)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = host
        panel.title = "Alto"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()
        self.panelWindow = panel
    }

    @objc func toggleCenteredPanel() {
        guard let panelWindow else { return }
        if panelWindow.isVisible {
            panelWindow.orderOut(nil)
            return
        }
        popoverVM.refresh()
        panelWindow.center()
        panelWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panelWindow.makeKey()
    }

    func reloadMenu() {
        popoverVM?.refresh()
    }
}
