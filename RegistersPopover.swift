import SwiftUI
import UniformTypeIdentifiers

struct RegistersPopover: View {
    @ObservedObject var vm: RegistersVM
    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 10) {
            // Header: search + clear-all
            HStack(spacing: 8) {
                TextField("Search registers…", text: $query)
                    .textFieldStyle(.roundedBorder)

                Button(role: .destructive) { vm.clearAll() } label: {
                    Image(systemName: "trash")
                }
                .help("Clear all registers")
            }

            // Drag to reorder; disabled while filtering
            List {
                ForEach(filtered) { item in
                    RegisterRowView(item: item, onClear: { vm.clear(item.index) })
                        .onDrag {
                            vm.beginDrag(id: item.id)
                            return NSItemProvider(object: item.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: RowDropDelegate(
                                targetID: item.id,
                                isEnabled: !isFiltering,
                                draggingID: { vm.draggingID },
                                onMove: { dragged, target in vm.move(draggedID: dragged, to: target) },
                                onDrop: { vm.commitReorder() }
                            )
                        )
                }
            }
            .listStyle(.plain)
            .frame(minWidth: 460, minHeight: 320)
        }
        .padding(12)
        .onAppear { vm.refresh() }
    }

    private var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filtered: [RegisterRow] {
        guard isFiltering else { return vm.rows }
        let q = query.lowercased()
        return vm.rows.filter { $0.preview.lowercased().contains(q) }
    }
}

// MARK: - Row view

private struct RegisterRowView: View {
    let item: RegisterRow
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("[\(item.index)]")
                    .font(.headline)
                    .monospaced()

                Text(item.preview)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .textSelection(.disabled)
            }

            HStack {
                Button("Clear", role: .destructive) { onClear() }
                Spacer()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - View model

struct RegisterRow: Identifiable, Equatable, Hashable {
    let id = UUID()
    let index: Int          // display number 1..9
    let preview: String
    let content: String     // full text to persist on reorder
}

final class RegistersVM: ObservableObject {
    @Published var rows: [RegisterRow] = []
    var draggingID: UUID?

    private let store: RegisterStore
    private let clipboard: ClipboardHelper

    init(store: RegisterStore, clipboard: ClipboardHelper) {
        self.store = store
        self.clipboard = clipboard
    }

    func refresh() {
        rows = (1...9).map { i in
            let t = store[i]
            let single = t.replacingOccurrences(of: "\n", with: " ⏎ ")
            let preview = single.isEmpty
                ? "(empty)"
                : (single.count > 160 ? String(single.prefix(160)) + "…" : single)
            return RegisterRow(index: i, preview: preview, content: t)
        }
    }

    func clear(_ i: Int) {
        store[i] = ""
        store.save()
        refresh()
        HUD.shared.show("Cleared reg \(i)")
    }

    func clearAll() {
        store.clearAll()
        refresh()
        HUD.shared.show("All registers cleared")
    }

    // Drag lifecycle
    func beginDrag(id: UUID) { draggingID = id }

    // Reorder the in-memory rows list by IDs (works regardless of filtering)
    func move(draggedID: UUID, to targetID: UUID) {
        guard let from = rows.firstIndex(where: { $0.id == draggedID }),
              let to   = rows.firstIndex(where: { $0.id == targetID }),
              from != to else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            let item = rows.remove(at: from)
            rows.insert(item, at: to)
        }
    }

    // Persist rows → registers so position == register number
    func commitReorder() {
        for (idx, row) in rows.enumerated() {
            store[idx + 1] = row.content   // row at 0 -> reg 1, etc.
        }
        store.save()
        refresh()  // rebuild rows with updated index labels [1..9]
        HUD.shared.show("Reordered registers")
    }
}

// MARK: - Drop delegate

private struct RowDropDelegate: DropDelegate {
    let targetID: UUID
    let isEnabled: Bool
    let draggingID: () -> UUID?
    let onMove: (UUID, UUID) -> Void
    let onDrop: () -> Void

    func validateDrop(info: DropInfo) -> Bool { isEnabled }

    func dropEntered(info: DropInfo) {
        guard isEnabled, let drag = draggingID(), drag != targetID else { return }
        onMove(drag, targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isEnabled else { return false }
        onDrop()
        return true
    }
}
