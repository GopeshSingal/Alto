import Foundation
import Carbon.HIToolbox

extension Notification.Name {
    static let KRSettingsChanged = Notification.Name("KRSettingsChanged")
}

final class SettingsStore: ObservableObject {
    struct Mods: Codable, Equatable {
        var cmd: Bool
        var opt: Bool
        var shift: Bool
        var ctrl: Bool
    }

    // Defaults: Paste = ⌘⌥, Save = ⌘⌥⇧
    @Published var pasteMods = Mods(cmd: true,  opt: true,  shift: false, ctrl: false) {
        didSet { persistAndNotify() }
    }
    @Published var saveMods  = Mods(cmd: true,  opt: true,  shift: true,  ctrl: false) {
        didSet { persistAndNotify() }
    }

    private struct Persist: Codable {
        var pasteMods: Mods
        var saveMods:  Mods
    }

    private static let defaultsKey = "KR.SettingsStore.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let persisted = try? JSONDecoder().decode(Persist.self, from: data) {
            self.pasteMods = persisted.pasteMods
            self.saveMods  = persisted.saveMods
        }
        // No Combine sinks needed; didSet handles persistence + notifications.
    }

    private func persistAndNotify() {
        let payload = Persist(pasteMods: pasteMods, saveMods: saveMods)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        NotificationCenter.default.post(name: .KRSettingsChanged, object: nil)
    }

    // MARK: - Carbon masks

    var pasteMask: UInt32 { mask(from: pasteMods) }
    var saveMask:  UInt32 { mask(from: saveMods)  }

    private func mask(from m: Mods) -> UInt32 {
        var v: UInt32 = 0
        if m.cmd   { v |= UInt32(cmdKey) }
        if m.opt   { v |= UInt32(optionKey) }
        if m.shift { v |= UInt32(shiftKey) }
        if m.ctrl  { v |= UInt32(controlKey) }
        return v
    }

    // Optional: keep users from disabling all modifiers (dangerous)
    func enforceAtLeastOneModifier() {
        if !(pasteMods.cmd || pasteMods.opt || pasteMods.shift || pasteMods.ctrl) {
            pasteMods = Mods(cmd: true, opt: true, shift: false, ctrl: false)
        }
        if !(saveMods.cmd || saveMods.opt || saveMods.shift || saveMods.ctrl) {
            saveMods = Mods(cmd: true, opt: true, shift: true, ctrl: false)
        }
    }

    func resetDefaults() {
        pasteMods = Mods(cmd: true, opt: true, shift: false, ctrl: false)
        saveMods  = Mods(cmd: true, opt: true, shift: true,  ctrl: false)
    }
}
