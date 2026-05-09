import Foundation

typealias PayloadMap = [String: Data]

final class RegisterStore {
    private(set) var slots: [PayloadMap] = (0..<10).map { _ in ClipboardPayload.empty() }

    subscript(index: Int) -> PayloadMap {
        get { (0..<slots.count).contains(index) ? slots[index] : ClipboardPayload.empty() }
        set { if (0..<slots.count).contains(index) { slots[index] = newValue } }
    }

    func clearAll() {
        for i in 0..<slots.count {
            slots[i] = ClipboardPayload.empty()
            try? FileManager.default.removeItem(at: slotURL(i))
        }
        save()
    }

    func swapRegisters(_ i: Int, _ j: Int) {
        guard i != j, (1...9).contains(i), (1...9).contains(j) else { return }
        slots.swapAt(i, j)
        save()
    }

    private var appSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyboardRegisters", isDirectory: true)
    }

    private var slotsDir: URL {
        appSupportDir.appendingPathComponent("slots", isDirectory: true)
    }

    private func slotURL(_ index: Int) -> URL {
        slotsDir.appendingPathComponent("\(index).plist")
    }

    private var legacyRegistersURL: URL {
        appSupportDir.appendingPathComponent("registers.json")
    }

    func load() {
        try? FileManager.default.createDirectory(at: slotsDir, withIntermediateDirectories: true)
        migrateLegacyJSONIfNeeded()

        for i in 0..<slots.count {
            slots[i] = loadSlotFile(i) ?? ClipboardPayload.empty()
        }
    }

    private func migrateLegacyJSONIfNeeded() {
        guard FileManager.default.fileExists(atPath: legacyRegistersURL.path) else { return }
        guard let data = try? Data(contentsOf: legacyRegistersURL),
              let arr = try? JSONDecoder().decode([String].self, from: data),
              arr.count == 10
        else {
            return
        }

        for i in 0..<10 {
            let s = arr[i]
            let payload = s.isEmpty ? ClipboardPayload.empty() : ClipboardPayload.plainText(s)
            writeSlotFile(i, payload: payload)
        }

        let backup = legacyRegistersURL.deletingLastPathComponent()
            .appendingPathComponent("registers.json.migrated")
        try? FileManager.default.moveItem(at: legacyRegistersURL, to: backup)
    }

    func save() {
        for i in 0..<slots.count {
            writeSlotFile(i, payload: slots[i])
        }
    }

    private func loadSlotFile(_ index: Int) -> PayloadMap? {
        let url = slotURL(index)
        guard FileManager.default.fileExists(atPath: url.path),
              let dict = NSDictionary(contentsOf: url) as? [String: Any]
        else { return nil }

        var out: PayloadMap = [:]
        for (keyStr, value) in dict {
            if let d = value as? Data {
                out[keyStr] = d
            } else if let d = value as? NSData {
                out[keyStr] = d as Data
            }
        }
        return out
    }

    private func writeSlotFile(_ index: Int, payload: PayloadMap) {
        let url = slotURL(index)
        if ClipboardPayload.isEmpty(payload) {
            try? FileManager.default.removeItem(at: url)
            return
        }
        (payload as NSDictionary).write(to: url, atomically: true)
    }
}
