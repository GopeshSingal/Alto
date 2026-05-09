import AppKit
import CryptoKit
import Foundation

/// Supported pasteboard representations for capture, storage, and paste.
enum ClipboardPayload {
    /// Maximum total raw bytes stored per slot/history item (before plist overhead).
    static let maxStoredBytes = 12 * 1024 * 1024

    static let whitelistTypes: [NSPasteboard.PasteboardType] = [
        .string,
        .init("public.utf8-plain-text"),
        .rtf,
        .html,
        .init("public.png"),
        .init("public.tiff"),
        .init("public.jpeg"),
        .init("com.compuserve.gif"),
    ]

    private static let imageTypeStrings: Set<String> = [
        "public.png", "public.tiff", "public.jpeg", "com.compuserve.gif",
        NSPasteboard.PasteboardType.png.rawValue,
        NSPasteboard.PasteboardType.tiff.rawValue,
    ]

    private static let richTypeStrings: Set<String> = [
        NSPasteboard.PasteboardType.rtf.rawValue,
        NSPasteboard.PasteboardType.html.rawValue,
    ]

    enum DominantKind: String {
        case text
        case rich
        case image
        case mixed
    }

    /// Canonical map: pasteboard type raw string -> data.
    static func empty() -> [String: Data] { [:] }

    static func isEmpty(_ map: [String: Data]) -> Bool {
        map.values.allSatisfy(\.isEmpty)
    }

    static func plainText(_ s: String) -> [String: Data] {
        guard let d = s.data(using: .utf8) else { return [:] }
        return [NSPasteboard.PasteboardType.string.rawValue: d]
    }

    /// Filters a full snapshot map down to whitelisted types (e.g. for comparing before/after copy).
    static func filterWhitelist(_ map: [String: Data]) -> [String: Data] {
        var out: [String: Data] = [:]
        for t in whitelistTypes {
            if let data = map[t.rawValue], !data.isEmpty {
                out[t.rawValue] = data
            }
        }
        dedupeImagePreference(&out)
        return out
    }

    /// Reads whitelisted types from the pasteboard; optionally drops TIFF when PNG exists.
    static func captureWhitelist(from pasteboard: NSPasteboard) -> [String: Data] {
        var out: [String: Data] = [:]
        guard let types = pasteboard.types else { return out }

        for t in whitelistTypes {
            guard types.contains(t) else { continue }
            if let data = pasteboard.data(forType: t), !data.isEmpty {
                out[t.rawValue] = data
            }
        }

        dedupeImagePreference(&out)
        return out
    }

    private static func dedupeImagePreference(_ map: inout [String: Data]) {
        let pngKey = NSPasteboard.PasteboardType.png.rawValue
        let tiffKey = NSPasteboard.PasteboardType.tiff.rawValue
        if map[pngKey] != nil, map[tiffKey] != nil {
            map.removeValue(forKey: tiffKey)
        }
    }

    /// If payload exceeds maxStoredBytes, shrink (drop images, then rich) while keeping plain text if possible.
    static func clampedForStorage(_ map: [String: Data]) -> [String: Data] {
        var m = map
        dedupeImagePreference(&m)
        if totalBytes(m) <= maxStoredBytes { return m }

        let plainKeys = m.keys.filter { k in
            k == NSPasteboard.PasteboardType.string.rawValue || k == "public.utf8-plain-text"
        }
        var plain: [String: Data] = [:]
        for k in plainKeys {
            if let v = m[k] { plain[k] = v }
        }

        if totalBytes(plain) <= maxStoredBytes {
            return plain
        }

        for k in m.keys where imageTypeStrings.contains(k) {
            m.removeValue(forKey: k)
            dedupeImagePreference(&m)
            if totalBytes(m) <= maxStoredBytes { return m }
        }
        for k in m.keys where richTypeStrings.contains(k) {
            m.removeValue(forKey: k)
            if totalBytes(m) <= maxStoredBytes { return m }
        }
        return plain.isEmpty ? m : plain
    }

    static func totalBytes(_ map: [String: Data]) -> Int {
        map.values.reduce(0) { $0 + $1.count }
    }

    static func dominantKind(_ map: [String: Data]) -> DominantKind {
        let keys = Set(map.keys)
        let hasImage = keys.contains { imageTypeStrings.contains($0) }
        let hasRich = keys.contains { richTypeStrings.contains($0) }
        let hasPlain = keys.contains {
            $0 == NSPasteboard.PasteboardType.string.rawValue || $0 == "public.utf8-plain-text"
        }

        let categories = [hasImage, hasRich, hasPlain].filter(\.self).count
        if categories > 1 { return .mixed }
        if hasImage { return .image }
        if hasRich { return .rich }
        return .text
    }

    static func hudLabel(for kind: DominantKind) -> String {
        switch kind {
        case .text: return "text"
        case .rich: return "rich text"
        case .image: return "image"
        case .mixed: return "clip"
        }
    }

    /// Plain-text line for search and list previews (best-effort).
    static func plainTextPreview(_ map: [String: Data], maxChars: Int) -> String {
        if let u = utf8String(from: map, type: NSPasteboard.PasteboardType.string.rawValue) {
            return truncatePreview(u, maxChars: maxChars)
        }
        if let u = utf8String(from: map, type: "public.utf8-plain-text") {
            return truncatePreview(u, maxChars: maxChars)
        }
        if let rtf = map[NSPasteboard.PasteboardType.rtf.rawValue],
           let s = plainFromRTF(rtf) {
            return truncatePreview(s, maxChars: maxChars)
        }
        if let html = map[NSPasteboard.PasteboardType.html.rawValue],
           let s = plainFromHTMLData(html) {
            return truncatePreview(s, maxChars: maxChars)
        }
        switch dominantKind(map) {
        case .image:
            return "(image)"
        case .rich:
            return "(rich text)"
        default:
            return ""
        }
    }

    private static func utf8String(from map: [String: Data], type: String) -> String? {
        guard let d = map[type], let s = String(data: d, encoding: .utf8) else { return nil }
        return s
    }

    private static func truncatePreview(_ s: String, maxChars: Int) -> String {
        let single = s.replacingOccurrences(of: "\n", with: " <nl> ")
        if single.count <= maxChars { return single }
        return String(single.prefix(maxChars)) + "..."
    }

    private static func plainFromRTF(_ data: Data) -> String? {
        guard let attr = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return nil }
        return attr.string
    }

    private static func plainFromHTMLData(_ data: Data) -> String? {
        guard let attr = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        ) else { return nil }
        return attr.string
    }

    /// True when an image representation exists that can be shown in the preview window.
    static func hasPreviewableImage(_ map: [String: Data]) -> Bool {
        orderedImageKeys.contains { key in
            if let d = map[key], !d.isEmpty { return NSImage(data: d) != nil }
            return false
        }
    }

    /// Full-size preview (optionally capped); uses the same decode order as thumbnails.
    static func previewNSImage(_ map: [String: Data], maxPx: CGFloat = 1280) -> NSImage? {
        thumbnailNSImage(map, maxPx: maxPx)
    }

    private static let orderedImageKeys: [String] = [
        NSPasteboard.PasteboardType.png.rawValue,
        NSPasteboard.PasteboardType.tiff.rawValue,
        "public.jpeg",
        "com.compuserve.gif",
    ]

    static func thumbnailNSImage(_ map: [String: Data], maxPx: CGFloat) -> NSImage? {
        for key in orderedImageKeys {
            guard let d = map[key], let img = NSImage(data: d) else { continue }
            return scaleDown(img, maxPx: maxPx)
        }
        return nil
    }

    private static func scaleDown(_ image: NSImage, maxPx: CGFloat) -> NSImage {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return image }
        let scale = min(maxPx / s.width, maxPx / s.height, 1)
        if scale >= 1 { return image }
        let newSize = NSSize(width: s.width * scale, height: s.height * scale)
        let img = NSImage(size: newSize)
        img.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: s),
            operation: .copy,
            fraction: 1
        )
        img.unlockFocus()
        return img
    }

    /// Stable fingerprint for deduplication.
    static func fingerprint(_ map: [String: Data]) -> String {
        let keys = map.keys.sorted()
        var combined = Data()
        for k in keys {
            combined.append(contentsOf: k.utf8)
            combined.append(0)
            combined.append(map[k] ?? Data())
        }
        let hash = SHA256.hash(data: combined)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Badge for list rows: "RTF", "HTML", "PNG", …
    static func formatBadge(_ map: [String: Data]) -> String? {
        switch dominantKind(map) {
        case .image:
            if map[NSPasteboard.PasteboardType.png.rawValue] != nil { return "PNG" }
            if map[NSPasteboard.PasteboardType.tiff.rawValue] != nil { return "TIFF" }
            if map["public.jpeg"] != nil { return "JPEG" }
            if map["com.compuserve.gif"] != nil { return "GIF" }
            return "Image"
        case .rich:
            if map[NSPasteboard.PasteboardType.rtf.rawValue] != nil { return "RTF" }
            if map[NSPasteboard.PasteboardType.html.rawValue] != nil { return "HTML" }
            return "Rich"
        default:
            return nil
        }
    }

    /// Writes payload types onto the pasteboard (after clearContents).
    static func write(_ map: [String: Data], to pasteboard: NSPasteboard) {
        for (typeStr, data) in map where !data.isEmpty {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(typeStr))
        }
    }

    /// Full pasteboard snapshot for faithful restore (all types present).
    static func captureFull(from pasteboard: NSPasteboard) -> [String: Data] {
        var out: [String: Data] = [:]
        guard let types = pasteboard.types else { return out }
        for t in types {
            if let d = pasteboard.data(forType: t), !d.isEmpty {
                out[t.rawValue] = d
            }
        }
        return out
    }

    static func restoreFull(_ map: [String: Data], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        write(map, to: pasteboard)
    }
}
