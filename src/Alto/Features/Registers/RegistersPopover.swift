import SwiftUI
import UniformTypeIdentifiers

struct RegistersPopover: View {
    @ObservedObject var vm: RegistersVM
    @State private var query: String = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("Search registers...", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)

                Button(role: .destructive) { vm.clearAll() } label: {
                    Image(systemName: "trash")
                }
                .help("Clear all registers")
            }

            List {
                ForEach(filtered) { item in
                    RegisterRowView(
                        item: item,
                        onClear: { vm.clear(item.index) },
                        onHoverChange: { hovering in
                            guard item.hasImagePreview else { return }
                            if hovering {
                                RegisterPreviewController.shared.hoverShow(
                                    payload: item.payload,
                                    registerIndex: item.index
                                )
                            } else {
                                RegisterPreviewController.shared.hoverEnd()
                            }
                        }
                    )
                    .onDrag {
                        vm.beginDrag(id: item.index)
                        return NSItemProvider(object: String(item.index) as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: RowDropDelegate(
                            targetID: item.index,
                            isEnabled: !isFiltering,
                            draggingID: { vm.draggingIndex },
                            onMove: { dragged, target in vm.move(draggedIndex: dragged, to: target) },
                            onDrop: { vm.commitReorder() }
                        )
                    )
                }
            }
            .listStyle(.plain)
            .frame(minWidth: 460, minHeight: 320)
        }
        .padding(12)
        .onAppear {
            vm.refresh()
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filtered: [RegisterRow] {
        guard isFiltering else { return vm.rows }
        let q = query.lowercased()
        return vm.rows.filter { row in
            ClipboardPayload.plainTextPreview(row.payload, maxChars: 10_000).lowercased().contains(q)
                || (row.badge?.lowercased().contains(q) ?? false)
        }
    }
}

private struct RegisterRowView: View {
    let item: RegisterRow
    let onClear: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if item.hasImagePreview {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .help(
                        "Hover to preview image — or Ctrl+A, V, \(item.index) (toggle; repeat to close)"
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("[\(item.index)]")
                            .font(.headline)
                            .monospaced()

                        if let badge = item.badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary.opacity(0.6))
                                .cornerRadius(4)
                        }

                        Text(item.preview)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .textSelection(.disabled)
                    }
                }
            }

            HStack {
                Button("Clear", role: .destructive) { onClear() }
                Spacer()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { onHoverChange($0) }
    }
}

struct RegisterRow: Identifiable {
    var id: Int { index }
    let index: Int
    let preview: String
    let badge: String?
    let payload: PayloadMap
    let hasImagePreview: Bool
}

final class RegistersVM: ObservableObject {
    @Published var rows: [RegisterRow] = []
    var draggingIndex: Int?

    private let store: RegisterStore

    init(store: RegisterStore) {
        self.store = store
    }

    func refresh() {
        rows = (1...9).map { i in
            let p = store[i]
            let empty = ClipboardPayload.isEmpty(p)
            let previewText = ClipboardPayload.plainTextPreview(p, maxChars: 160)
            let preview: String = {
                if empty { return "(empty)" }
                if previewText.isEmpty {
                    return "(\(ClipboardPayload.dominantKind(p).rawValue))"
                }
                return previewText
            }()
            let badge = ClipboardPayload.formatBadge(p)
            let hasImage = ClipboardPayload.hasPreviewableImage(p)
            return RegisterRow(
                index: i,
                preview: preview,
                badge: badge,
                payload: p,
                hasImagePreview: hasImage
            )
        }
    }

    func clear(_ i: Int) {
        store[i] = ClipboardPayload.empty()
        store.save()
        refresh()
        HUD.shared.show("Cleared reg \(i)")
    }

    func clearAll() {
        store.clearAll()
        refresh()
        HUD.shared.show("All registers cleared")
    }

    func beginDrag(id: Int) {
        draggingIndex = id
    }

    func move(draggedIndex: Int, to targetIndex: Int) {
        guard let from = rows.firstIndex(where: { $0.index == draggedIndex }),
              let to = rows.firstIndex(where: { $0.index == targetIndex }),
              from != to
        else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            let item = rows.remove(at: from)
            rows.insert(item, at: to)
        }
    }

    func commitReorder() {
        for (idx, row) in rows.enumerated() {
            store[idx + 1] = row.payload
        }
        store.save()
        refresh()
        HUD.shared.show("Reordered registers")
    }
}

private struct RowDropDelegate: DropDelegate {
    let targetID: Int
    let isEnabled: Bool
    let draggingID: () -> Int?
    let onMove: (Int, Int) -> Void
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
