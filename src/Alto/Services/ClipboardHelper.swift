import Cocoa
import Carbon.HIToolbox

final class ClipboardHelper {
    func pasteText(_ text: String) {
        guard !text.isEmpty else { return }
        let old = NSPasteboard.general.string(forType: .string)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        sendKeyCombo(cmd: true, key: kVK_ANSI_V)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSPasteboard.general.clearContents()
            if let old {
                NSPasteboard.general.setString(old, forType: .string)
            }
        }
    }

    func captureSelection(done: @escaping (_ text: String, _ changed: Bool) -> Void) {
        let beforeCount = NSPasteboard.general.changeCount
        let old = NSPasteboard.general.string(forType: .string)
        sendKeyCombo(cmd: true, key: kVK_ANSI_C)

        let start = Date()
        func poll() {
            let changed = NSPasteboard.general.changeCount != beforeCount
            if changed || Date().timeIntervalSince(start) > 1.0 {
                let grabbed = NSPasteboard.general.string(forType: .string) ?? ""
                let succeeded = changed || (!grabbed.isEmpty && grabbed != old)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    NSPasteboard.general.clearContents()
                    if let old {
                        NSPasteboard.general.setString(old, forType: .string)
                    }
                }
                done(grabbed, succeeded)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: poll)
            }
        }
        poll()
    }

    func sendKeyCombo(cmd: Bool = false, alt: Bool = false, shift: Bool = false, key: Int) {
        func event(_ key: Int, _ down: Bool) -> CGEvent {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: down)!
            var flags = CGEventFlags()
            if cmd { flags.insert(.maskCommand) }
            if alt { flags.insert(.maskAlternate) }
            if shift { flags.insert(.maskShift) }
            e.flags = flags
            return e
        }
        event(key, true).post(tap: .cghidEventTap)
        event(key, false).post(tap: .cghidEventTap)
    }
}
