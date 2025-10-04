import AppKit

/// Polls NSPasteboard.changeCount and records plain-text changes into ClipboardHistoryStore.
final class ClipboardWatcher {
    private let pb = NSPasteboard.general
    private var lastChange: Int = -1
    private var timer: Timer?
    private let store: ClipboardHistoryStore

    /// Poll interval (seconds). 0.5s is responsive without being wasteful.
    var interval: TimeInterval = 0.5

    init(store: ClipboardHistoryStore) {
        self.store = store
    }

    func start() {
        stop()
        lastChange = pb.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let cc = pb.changeCount
        guard cc != lastChange else { return }
        lastChange = cc

        // Capture plain text flavor; ignore others for now
        if let s = pb.string(forType: .string) {
            store.add(text: s)
        }
    }
}
