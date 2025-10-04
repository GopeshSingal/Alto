import SwiftUI
import AppKit

// MARK: - View

struct HistoryTab: View {
    @ObservedObject var vm: HistoryVM
    @State private var query: String = ""

    // Present the sheet by binding directly to the item we want to save.
    @State private var pending: HistoryItem?

    var body: some View {
        VStack(spacing: 10) {
            // Header: search + clear-all
            HStack(spacing: 8) {
                TextField("Search history…", text: $query)
                    .textFieldStyle(.roundedBorder)

                Button(role: .destructive) { vm.clearAll() } label: {
                    Image(systemName: "trash")
                }
                .help("Clear all history")

                Spacer()
                Button("Quit") { NSApp.terminate(nil) } // optional convenience
            }

            List(filtered) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.date, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save") { pending = item } // open chooser
                        Button("Delete", role: .destructive) { vm.delete(item) }
                    }
                    Text(preview(item.text))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
            .frame(minWidth: 520, minHeight: 340)
        }
        .padding(12)
        .onAppear { vm.refresh() }

        // ✅ Present sheet only when `pending` has a value.
        .sheet(item: $pending) { item in
            KeyPrompt(
                message: "Press 1–9 to save into that register.\n(Press 0 or Esc to cancel)",
                onNumber: { n in
                    defer { self.pending = nil } // close sheet in all cases
                    guard (1...9).contains(n) else { return } // ignore 0/cancel/other
                    vm.saveHistoryItem(item, toRegister: n)    // safe: 1..9 only
                }
            )
            .interactiveDismissDisabled()        // don’t allow swipe-away to avoid half states
            .frame(width: 360, height: 120)
        }
    }

    private func preview(_ s: String) -> String {
        let single = s.replacingOccurrences(of: "\n", with: " ⏎ ")
        return single.count > 240 ? String(single.prefix(240)) + "…" : single
    }

    private var filtered: [HistoryItem] {
        let items = vm.items
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.text.lowercased().contains(q) }
    }
}

// MARK: - Keyboard-only chooser (swallows all non-handled keys)

private struct KeyPrompt: View {
    let message: String
    let onNumber: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Save to Register").font(.headline)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(KeyCatcher(onNumber: onNumber))
    }
}

private struct KeyCatcher: NSViewRepresentable {
    final class View_: NSView {
        var onNumber: ((Int) -> Void)?

        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            // Only handle digits and Esc; swallow everything else (no super.keyDown)
            if let chars = event.characters, let c = chars.first, c.isNumber {
                if let val = Int(String(c)) {
                    onNumber?(val)
                    return
                }
            }
            if event.keyCode == 53 { // Esc
                onNumber?(0)
                return
            }
            // Swallow any other key to prevent leaking into other views/apps
        }
    }

    var onNumber: (Int) -> Void

    func makeNSView(context: Context) -> View_ {
        let v = View_()
        v.onNumber = onNumber
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.clear.cgColor
        return v
    }

    func updateNSView(_ nsView: View_, context: Context) {
        nsView.onNumber = onNumber
    }
}

// MARK: - ViewModel (unchanged)

final class HistoryVM: ObservableObject {
    @Published var items: [HistoryItem] = []

    private let historyStore: ClipboardHistoryStore
    private let registerStore: RegisterStore

    init(historyStore: ClipboardHistoryStore, registerStore: RegisterStore) {
        self.historyStore = historyStore
        self.registerStore = registerStore
        historyStore.$items.receive(on: RunLoop.main).assign(to: &self.$items)
    }

    func refresh() { items = historyStore.items }
    func delete(_ item: HistoryItem) { historyStore.remove(id: item.id) }
    func clearAll() { historyStore.clearAll() }

    func saveHistoryItem(_ item: HistoryItem, toRegister n: Int) {
        guard (1...9).contains(n) else { return }
        registerStore[n] = item.text
        registerStore.save()
        HUD.shared.show("Saved history → reg \(n)")
    }
}
