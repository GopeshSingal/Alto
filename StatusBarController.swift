import Cocoa
import SwiftUI

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let store: RegisterStore
    private let clipboard: ClipboardHelper
    private let settings: SettingsStore
    private let historyStore: ClipboardHistoryStore

    private let popover = NSPopover()
    private var popoverVM: RegistersVM!

    init(store: RegisterStore,
         clipboard: ClipboardHelper,
         historyStore: ClipboardHistoryStore,
         settings: SettingsStore) {
        self.store = store
        self.clipboard = clipboard
        self.historyStore = historyStore
        self.settings = settings

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⌘#"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popoverVM = RegistersVM(store: store, clipboard: clipboard)
        let historyVM = HistoryVM(historyStore: historyStore, registerStore: store)

        let root = TabView {
            RegistersPopover(vm: popoverVM)
                .tabItem { Label("Registers", systemImage: "number") }

            HistoryTab(vm: historyVM)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            SettingsTab(settings: settings)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .padding(.top, 4)

        popover.contentViewController = NSHostingController(rootView: root)
        popover.behavior = .transient
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popoverVM.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            if let window = popover.contentViewController?.view.window {
                var frame = window.frame
                frame.origin.y -= 100
                window.setFrame(frame, display: true)
            }
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    

    func toast(_ msg: String) { HUD.shared.show(msg) }
    func reloadMenu() { popoverVM?.refresh() }
}
