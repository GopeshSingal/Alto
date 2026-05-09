import Cocoa
import Carbon.HIToolbox

final class ClipboardHelper {
    func pastePayload(_ map: [String: Data]) {
        guard !ClipboardPayload.isEmpty(map) else { return }
        let previous = ClipboardPayload.captureFull(from: NSPasteboard.general)
        NSPasteboard.general.clearContents()
        ClipboardPayload.write(map, to: NSPasteboard.general)
        sendKeyCombo(cmd: true, key: kVK_ANSI_V)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ClipboardPayload.restoreFull(previous, to: NSPasteboard.general)
        }
    }

    func captureSelection(done: @escaping (_ payload: [String: Data], _ changed: Bool) -> Void) {
        let beforeCount = NSPasteboard.general.changeCount
        let previous = ClipboardPayload.captureFull(from: NSPasteboard.general)
        let previousWhitelist = ClipboardPayload.filterWhitelist(previous)
        sendKeyCombo(cmd: true, key: kVK_ANSI_C)

        let start = Date()
        func poll() {
            let changed = NSPasteboard.general.changeCount != beforeCount
            if changed || Date().timeIntervalSince(start) > 1.0 {
                let grabbedWhitelist = ClipboardPayload.captureWhitelist(from: NSPasteboard.general)
                let clamped = ClipboardPayload.clampedForStorage(grabbedWhitelist)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    ClipboardPayload.restoreFull(previous, to: NSPasteboard.general)
                }

                let hasPayload = !ClipboardPayload.isEmpty(clamped)
                let differsFromBefore =
                    ClipboardPayload.fingerprint(clamped) != ClipboardPayload.fingerprint(previousWhitelist)
                let succeeded =
                    hasPayload && (changed ? true : differsFromBefore)

                done(clamped, succeeded)
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
