import Foundation

struct HistoryItem: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let fingerprint: String
    let payload: PayloadMap

    init(id: UUID = UUID(), date: Date = Date(), payload: PayloadMap) {
        self.id = id
        self.date = date
        self.payload = payload
        self.fingerprint = ClipboardPayload.fingerprint(payload)
    }
}

final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []
    var maxItems: Int = 1000

    private struct ManifestEntry: Codable {
        let id: UUID
        let date: Date
        let fingerprint: String
    }

    private struct LegacyHistoryRow: Codable {
        let id: UUID
        let text: String
        let date: Date
    }

    private var appSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyboardRegisters", isDirectory: true)
    }

    private var manifestURL: URL {
        appSupportDir.appendingPathComponent("history_manifest.json")
    }

    private var payloadsDir: URL {
        appSupportDir.appendingPathComponent("history_payloads", isDirectory: true)
    }

    private var legacyHistoryURL: URL {
        appSupportDir.appendingPathComponent("history.json")
    }

    func load() {
        try? FileManager.default.createDirectory(at: payloadsDir, withIntermediateDirectories: true)
        migrateLegacyHistoryIfNeeded()

        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([ManifestEntry].self, from: data)
        else {
            items = []
            return
        }

        items = entries.compactMap { entry in
            guard let payload = loadPayloadFile(id: entry.id) else { return nil }
            return HistoryItem(id: entry.id, date: entry.date, payload: payload)
        }
    }

    func save() {
        try? FileManager.default.createDirectory(at: payloadsDir, withIntermediateDirectories: true)

        let entries = items.map {
            ManifestEntry(
                id: $0.id,
                date: $0.date,
                fingerprint: ClipboardPayload.fingerprint($0.payload)
            )
        }

        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: manifestURL, options: .atomic)
        }

        for item in items {
            writePayloadFile(id: item.id, payload: item.payload)
        }
    }

    func add(payload: PayloadMap) {
        guard !ClipboardPayload.isEmpty(payload) else { return }
        let clamped = ClipboardPayload.clampedForStorage(payload)
        guard !ClipboardPayload.isEmpty(clamped) else { return }

        let fp = ClipboardPayload.fingerprint(clamped)
        if let last = items.first, last.fingerprint == fp { return }

        items.insert(HistoryItem(payload: clamped), at: 0)
        while items.count > maxItems {
            let removed = items.removeLast()
            try? FileManager.default.removeItem(at: payloadURL(removed.id))
        }
        save()
    }

    func clearAll() {
        for item in items {
            try? FileManager.default.removeItem(at: payloadURL(item.id))
        }
        items.removeAll()
        try? FileManager.default.removeItem(at: manifestURL)
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: payloadURL(id))
        save()
    }

    private func payloadURL(_ id: UUID) -> URL {
        payloadsDir.appendingPathComponent("\(id.uuidString).plist")
    }

    private func loadPayloadFile(id: UUID) -> PayloadMap? {
        let url = payloadURL(id)
        guard FileManager.default.fileExists(atPath: url.path),
              let dict = NSDictionary(contentsOf: url) as? [String: Any]
        else { return nil }

        var out: PayloadMap = [:]
        for (key, value) in dict {
            let keyStr = key
            if let d = value as? Data {
                out[keyStr] = d
            } else if let d = value as? NSData {
                out[keyStr] = d as Data
            }
        }
        return out
    }

    private func writePayloadFile(id: UUID, payload: PayloadMap) {
        let url = payloadURL(id)
        if ClipboardPayload.isEmpty(payload) {
            try? FileManager.default.removeItem(at: url)
            return
        }
        (payload as NSDictionary).write(to: url, atomically: true)
    }

    private func migrateLegacyHistoryIfNeeded() {
        guard FileManager.default.fileExists(atPath: legacyHistoryURL.path) else { return }

        guard let data = try? Data(contentsOf: legacyHistoryURL),
              let legacy = try? JSONDecoder().decode([LegacyHistoryRow].self, from: data)
        else {
            return
        }

        var entries: [ManifestEntry] = []
        for row in legacy {
            let payload = ClipboardPayload.plainText(row.text)
            let fp = ClipboardPayload.fingerprint(payload)
            entries.append(ManifestEntry(id: row.id, date: row.date, fingerprint: fp))
            writePayloadFile(id: row.id, payload: payload)
        }

        if let enc = try? JSONEncoder().encode(entries) {
            try? enc.write(to: manifestURL, options: .atomic)
        }

        let backup = appSupportDir.appendingPathComponent("history.json.migrated")
        try? FileManager.default.moveItem(at: legacyHistoryURL, to: backup)
    }
}
