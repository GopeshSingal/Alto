import Cocoa
import Carbon.HIToolbox

final class ClipboardHelper {
    /// Paste text without permanently overwriting the user's clipboard.
    func pasteText(_ text: String) {
        guard !text.isEmpty else { return }
        let old = NSPasteboard.general.string(forType: .string)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        sendKeyCombo(cmd: true, key: kVK_ANSI_V)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSPasteboard.general.clearContents()
            if let old { NSPasteboard.general.setString(old, forType: .string) }
        }
    }

    /// Simulate ⌘C, wait for pasteboard to change, restore the old clipboard, then call back.
    func captureSelection(done: @escaping (_ text: String, _ changed: Bool) -> Void) {
        let beforeCount = NSPasteboard.general.changeCount
        let old = NSPasteboard.general.string(forType: .string)
        sendKeyCombo(cmd: true, key: kVK_ANSI_C)

        let start = Date()
        func poll() {
            let changed = NSPasteboard.general.changeCount != beforeCount
            if changed || Date().timeIntervalSince(start) > 0.6 {
                let grabbed = NSPasteboard.general.string(forType: .string) ?? ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    NSPasteboard.general.clearContents()
                    if let old { NSPasteboard.general.setString(old, forType: .string) }
                }
                done(grabbed, changed)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: poll)
            }
        }
        poll()
    }

    /// Synthesize keypresses (needs Accessibility permission).
    func sendKeyCombo(cmd: Bool = false, alt: Bool = false, shift: Bool = false, key: Int) {
        func ev(_ key: Int, _ down: Bool) -> CGEvent {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: down)!
            var flags = CGEventFlags()
            if cmd { flags.insert(.maskCommand) }
            if alt { flags.insert(.maskAlternate) }
            if shift { flags.insert(.maskShift) }
            e.flags = flags
            return e
        }
        ev(key, true).post(tap: .cghidEventTap)
        ev(key, false).post(tap: .cghidEventTap)
    }
}
