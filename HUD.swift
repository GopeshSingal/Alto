import Cocoa
import QuartzCore

/// A NSVisualEffectView that makes the window draggable by clicking anywhere on it.
final class DraggableHUDView: NSVisualEffectView {
    override func mouseDown(with event: NSEvent) {
        // Begin a window drag from wherever the user clicks
        self.window?.performDrag(with: event)
    }
}

/// Lightweight movable HUD panel. Call HUD.shared.show("message").
final class HUD {
    static let shared = HUD()

    private var window: NSPanel?
    private let container = DraggableHUDView()
    private let label = NSTextField(labelWithString: "")
    private var fadeTimer: Timer?

    private let defaultsKeyFrame = "KR.HUD.lastFrame"

    private init() {
        // Content (blurred, rounded, draggable)
        container.material = .hudWindow
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        // Label
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])

        // Create a floating, movable panel (independent from the menu bar)
        let initialFrame = NSRect(x: 0, y: 0, width: 260, height: 48)
        let p = NSPanel(contentRect: initialFrame,
                        styleMask: [.titled, .utilityWindow, .fullSizeContentView],
                        backing: .buffered,
                        defer: false)

        p.title = ""
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .floating                 // not status bar; independent
        p.hasShadow = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        p.isMovable = true
        p.isMovableByWindowBackground = true

        // Keep only the close button if you want (optional)
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true

        // Important: do NOT set ignoresMouseEvents = true — we need clicks to drag
        p.contentView = container
        self.window = p

        // Restore last position if we have it
        if let f = Self.loadFrame(from: defaultsKeyFrame) {
            p.setFrame(f, display: false)
        }
    }

    /// Show a message. Pass duration = 0 to keep it visible until closed.
    func show(_ text: String, duration: TimeInterval = 0.9) {
        DispatchQueue.main.async {
            guard let window = self.window else { return }

            self.label.stringValue = text

            // Size to fit text (cap width/height)
            let maxWidth: CGFloat = 480
            let size = self.label.attributedStringValue.size()
            let targetW = min(maxWidth, max(180, size.width + 28))
            let targetH = max(36, min(240, size.height + 20))

            var frame = window.frame
            let hadSavedFrame = !Self.noSavedFrame(self.defaultsKeyFrame)
            let oldOrigin = frame.origin
            frame.size = NSSize(width: targetW, height: targetH)

            if !hadSavedFrame {
                // First time: place near top-center, but it's movable now
                let screen = NSScreen.main ?? NSScreen.screens.first!
                let vf = screen.visibleFrame
                frame.origin.x = vf.midX - frame.width / 2
                frame.origin.y = vf.maxY - frame.height - 80
            } else {
                frame.origin = oldOrigin
            }

            window.setFrame(frame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                window.animator().alphaValue = 1
            })

            // Timer-based fade (0 => sticky)
            self.fadeTimer?.invalidate()
            if duration > 0 {
                self.fadeTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                    self?.hideAnimated()
                }
                RunLoop.main.add(self.fadeTimer!, forMode: .common)
            }
        }
    }

    func hide() {
        guard let window = window else { return }
        window.orderOut(nil)
        cleanup()
    }

    private func hideAnimated() {
        guard let window = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.20
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
        cleanup()
    }

    private func cleanup() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        if let w = window {
            Self.saveFrame(w.frame, to: defaultsKeyFrame)
        }
    }

    // MARK: - Frame persistence
    private static func saveFrame(_ frame: NSRect, to key: String) {
        let dict: [String: CGFloat] = ["x": frame.origin.x, "y": frame.origin.y, "w": frame.size.width, "h": frame.size.height]
        UserDefaults.standard.set(dict, forKey: key)
    }
    private static func loadFrame(from key: String) -> NSRect? {
        guard let d = UserDefaults.standard.dictionary(forKey: key) as? [String: CGFloat],
              let x = d["x"], let y = d["y"], let w = d["w"], let h = d["h"] else { return nil }
        return NSRect(x: x, y: y, width: w, height: h)
    }
    private static func noSavedFrame(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil
    }
}
