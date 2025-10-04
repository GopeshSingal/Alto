import Foundation

struct HistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date

    init(id: UUID = UUID(), text: String, date: Date = Date()) {
        self.id = id
        self.text = text
        self.date = date
    }
}

final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []
    var maxItems: Int = 1000

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("KeyboardRegisters", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return }
        if let arr = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = arr
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Record an entry when a user **saves into a register**.
    func add(text: String) {
        let trimmed = text
        guard !trimmed.isEmpty else { return }
        if let last = items.first, last.text == trimmed { return } // de-dupe consecutive
        items.insert(HistoryItem(text: trimmed), at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        save()
    }

    func clearAll() {
        items.removeAll()
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }
}
