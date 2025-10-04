import Foundation

/// 10 slots; index 0 is reserved (not used as a register).
final class RegisterStore {
    private(set) var slots: [String] = Array(repeating: "", count: 10)

    subscript(index: Int) -> String {
        get { (0..<slots.count).contains(index) ? slots[index] : "" }
        set { if (0..<slots.count).contains(index) { slots[index] = newValue } }
    }

    func clearAll() {
        for i in 0..<slots.count { slots[i] = "" }
        save()
    }

    // Persistence: ~/Library/Application Support/KeyboardRegisters/registers.json
    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("KeyboardRegisters", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("registers.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let arr = try? JSONDecoder().decode([String].self, from: data), arr.count == 10 {
            slots = arr
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(slots) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
