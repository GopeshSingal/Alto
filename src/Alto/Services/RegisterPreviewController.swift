import AppKit

/// Floating window that shows a large image preview for a register payload.
final class RegisterPreviewController: NSObject {
    static let shared = RegisterPreviewController()

    private var panel: NSPanel?
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let container = PreviewContentView()
    private var hideWorkItem: DispatchWorkItem?
    private var showWorkItem: DispatchWorkItem?
    private var escapeMonitor: Any?

    /// When non-nil, the preview window was pinned by Ctrl+A+V+number and stays open until toggled again.
    private var pinnedHotkeyRegister: Int?

    private let showDelay: TimeInterval = 0.14
    private let hideDelay: TimeInterval = 0.35
    private let maxContentWidth: CGFloat = 680
    private let maxContentHeight: CGFloat = 620
    private let padding: CGFloat = 14

    private override init() {
        super.init()
        container.controller = self
    }

    func showFromHotkey(payload: PayloadMap, registerIndex: Int) {
        cancelScheduledShow()
        cancelScheduledHide()

        if pinnedHotkeyRegister == registerIndex, panel?.isVisible == true {
            hide()
            return
        }

        guard ClipboardPayload.hasPreviewableImage(payload),
              let image = ClipboardPayload.previewNSImage(payload, maxPx: 1600)
        else {
            HUD.shared.show("No image preview for reg \(registerIndex)")
            return
        }

        pinnedHotkeyRegister = registerIndex
        present(image: image, registerIndex: registerIndex, anchorMouse: NSEvent.mouseLocation)
    }

    func hoverShow(payload: PayloadMap, registerIndex: Int) {
        guard pinnedHotkeyRegister == nil else { return }
        guard ClipboardPayload.hasPreviewableImage(payload) else { return }
        cancelScheduledHide()
        cancelScheduledShow()
        let mouse = NSEvent.mouseLocation
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  let image = ClipboardPayload.previewNSImage(payload, maxPx: 1600)
            else { return }
            self.present(image: image, registerIndex: registerIndex, anchorMouse: mouse)
        }
        showWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showDelay, execute: work)
    }

    func hoverEnd() {
        guard pinnedHotkeyRegister == nil else {
            cancelScheduledShow()
            cancelScheduledHide()
            return
        }
        cancelScheduledShow()
        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: work)
    }

    fileprivate func panelMouseEntered() {
        cancelScheduledHide()
    }

    fileprivate func panelMouseExited() {
        if pinnedHotkeyRegister != nil { return }
        hoverEnd()
    }

    private func cancelScheduledShow() {
        showWorkItem?.cancel()
        showWorkItem = nil
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func present(image: NSImage, registerIndex: Int, anchorMouse: NSPoint) {
        cancelScheduledShow()
        cancelScheduledHide()

        ensurePanel()
        guard let panel else { return }

        titleLabel.stringValue = "Register \(registerIndex)"
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown

        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return }

        let scale = min(
            1,
            maxContentWidth / imgSize.width,
            maxContentHeight / imgSize.height
        )
        let contentW = max(120, imgSize.width * scale)
        let contentH = max(80, imgSize.height * scale)
        let titleH: CGFloat = 22
        let innerW = contentW + padding * 2
        let innerH = titleH + contentH + padding * 2

        titleLabel.frame = NSRect(x: padding, y: padding, width: innerW - padding * 2, height: titleH)
        imageView.frame = NSRect(x: padding, y: padding + titleH, width: contentW, height: contentH)
        container.frame = NSRect(origin: .zero, size: NSSize(width: innerW, height: innerH))

        panel.setContentSize(NSSize(width: innerW, height: innerH))

        var origin = NSPoint(
            x: anchorMouse.x - innerW / 2,
            y: anchorMouse.y - innerH - 28
        )

        if let screen = NSScreen.screens.first(where: { NSMouseInRect(anchorMouse, $0.frame, false) })
            ?? NSScreen.main
        {
            let vf = screen.visibleFrame
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - innerW - 8)
            origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - innerH - 8)
        }

        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        installEscapeMonitor()
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        container.addSubview(titleLabel)
        container.addSubview(imageView)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "Image preview"
        p.isFloatingPanel = true
        p.level = .floating
        p.becomesKeyOnlyIfNeeded = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = container
        p.delegate = self

        panel = p
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.hide()
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
    }

    func hide() {
        pinnedHotkeyRegister = nil
        cancelScheduledShow()
        cancelScheduledHide()
        removeEscapeMonitor()
        panel?.orderOut(nil)
    }

    private final class PreviewContentView: NSView {
        weak var controller: RegisterPreviewController?
        private var hoverTracking: NSTrackingArea?

        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverTracking {
                removeTrackingArea(hoverTracking)
            }
            let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .inVisibleRect]
            let ta = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(ta)
            hoverTracking = ta
        }

        override func mouseEntered(with event: NSEvent) {
            controller?.panelMouseEntered()
        }

        override func mouseExited(with event: NSEvent) {
            controller?.panelMouseExited()
        }
    }
}

extension RegisterPreviewController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        hide()
    }
}
