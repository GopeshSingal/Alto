import SwiftUI
import AppKit

struct HistoryTab: View {
    @ObservedObject var vm: HistoryVM
    @State private var query: String = ""
    @State private var pending: HistoryItem?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("Search history...", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)

                Button(role: .destructive) { vm.clearAll() } label: {
                    Image(systemName: "trash")
                }
                .help("Clear all history")

                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }

            List(filtered) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.date, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save") { pending = item }
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
        .onAppear {
            vm.refresh()
            DispatchQueue.main.async { searchFocused = true }
        }
        .sheet(item: $pending) { item in
            KeyPrompt(
                message: "Press 1-9 to save into that register.\n(Press 0 or Esc to cancel)",
                onNumber: { n in
                    defer { self.pending = nil }
                    guard (1...9).contains(n) else { return }
                    vm.saveHistoryItem(item, toRegister: n)
                }
            )
            .interactiveDismissDisabled()
            .frame(width: 360, height: 120)
        }
    }

    private func preview(_ s: String) -> String {
        let single = s.replacingOccurrences(of: "\n", with: " <nl> ")
        return single.count > 240 ? String(single.prefix(240)) + "..." : single
    }

    private var filtered: [HistoryItem] {
        let items = vm.items
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.text.lowercased().contains(q) }
    }
}

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
            if let chars = event.characters, let c = chars.first, c.isNumber, let val = Int(String(c)) {
                onNumber?(val)
                return
            }
            if event.keyCode == 53 {
                onNumber?(0)
            }
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
        HUD.shared.show("Saved history -> reg \(n)")
    }
}
