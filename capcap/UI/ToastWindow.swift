import AppKit

class ToastWindow: NSPanel {
    private static var current: ToastWindow?
    private var operationID = ""
    private var dismissal: DispatchWorkItem?
    private var revision = 0

    struct Context {
        var screen: NSScreen?
        var anchor: NSPoint?
        var operationID: String

        init(view: NSView?, operationID: String = "history-copy") {
            let window = view?.window
            screen = window?.screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            if let view, let window {
                let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
                anchor = NSPoint(x: rect.midX, y: rect.minY)
            }
            self.operationID = "\(operationID)/\(window?.windowNumber ?? 0)"
        }

        func show(_ message: String, duration: TimeInterval = 1.5) {
            ToastWindow.show(message: message, on: screen, topAnchor: anchor,
                             duration: duration, operationID: operationID)
        }
    }

    static var captureExcludedWindowNumbers: [CGWindowID] {
        if Thread.isMainThread {
            return captureExcludedWindowNumbersOnMain()
        }
        return DispatchQueue.main.sync {
            captureExcludedWindowNumbersOnMain()
        }
    }

    /// Shows a transient toast. When `topAnchor` is set (a point in screen
    /// coordinates), the toast hangs just below that point with its horizontal
    /// center aligned to it — used to pin the hint to the top-center of a
    /// selection. When `centerAnchor` is set, the toast is centered on that
    /// point — used to place the hint in the middle of a selection. Otherwise
    /// the toast is centered on `screen`.
    static func show(
        message: String = L10n.copiedToClipboard,
        on screen: NSScreen? = nil,
        topAnchor: NSPoint? = nil,
        centerAnchor: NSPoint? = nil,
        duration: TimeInterval = 1.5,
        operationID: String = UUID().uuidString
    ) {
        let screen = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let sameOperation = current?.operationID == operationID
        let toast: ToastWindow
        if sameOperation, let existing = current {
            toast = existing
        } else {
            current?.dismissal?.cancel()
            current?.orderOut(nil)
            toast = ToastWindow(message: message)
        }
        toast.dismissal?.cancel()
        toast.operationID = operationID
        toast.revision += 1
        let revision = toast.revision
        current = toast
        toast.setMessage(message, maximumWidth: min(420, (screen?.visibleFrame.width ?? 440) - 24))

        var frame = toast.frame
        if let anchor = topAnchor {
            frame.origin = NSPoint(x: anchor.x - frame.width / 2, y: anchor.y - frame.height - 12)
        } else if let anchor = centerAnchor {
            frame.origin = NSPoint(x: anchor.x - frame.width / 2, y: anchor.y - frame.height / 2)
        } else if let screen {
            frame.origin = NSPoint(x: screen.visibleFrame.midX - frame.width / 2,
                                   y: screen.visibleFrame.midY - frame.height / 2)
        }
        if let visible = screen?.visibleFrame.insetBy(dx: 8, dy: 8) {
            frame.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
            frame.origin.y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
        }
        toast.setFrame(frame, display: true)
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !sameOperation { toast.alphaValue = reducedMotion ? 1 : 0 }
        toast.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducedMotion ? 0 : 0.16
            toast.animator().alphaValue = 1
        }
        let dismissal = DispatchWorkItem { [weak toast] in
            guard let toast, current === toast, toast.revision == revision else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
                toast.animator().alphaValue = 0
            }, completionHandler: { [weak toast] in
                guard let toast, current === toast, toast.revision == revision else { return }
                toast.orderOut(nil)
                current = nil
            })
        }
        toast.dismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: dismissal)
    }

    /// Async completions may dismiss only the progress hint they own.
    static func dismiss(operationID: String) {
        guard current?.operationID == operationID else { return }
        dismiss()
    }

    /// Immediately hides any visible toast. Safe to call when none is showing.
    static func dismiss() {
        _ = dismissForCaptureIfNeeded()
    }

    @discardableResult
    static func dismissForCaptureIfNeeded() -> Bool {
        if Thread.isMainThread {
            return dismissForCaptureIfNeededOnMain()
        }
        return DispatchQueue.main.sync {
            dismissForCaptureIfNeededOnMain()
        }
    }

    private static func captureExcludedWindowNumbersOnMain() -> [CGWindowID] {
        guard let window = current, window.isVisible else { return [] }
        let windowNumber = window.windowNumber
        guard windowNumber > 0 else { return [] }
        return [CGWindowID(windowNumber)]
    }

    private static func dismissForCaptureIfNeededOnMain() -> Bool {
        guard let window = current, window.isVisible else {
            current = nil
            return false
        }
        window.dismissal?.cancel()
        window.orderOut(nil)
        current = nil
        return true
    }

    private func setMessage(_ message: String, maximumWidth: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]
        let textSize = (message as NSString).boundingRect(
            with: NSSize(width: max(80, maximumWidth - 24), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes).size
        let size = NSSize(width: min(maximumWidth, ceil(textSize.width) + 24), height: max(32, ceil(textSize.height) + 16))
        setContentSize(size)
        contentView = ToastContentView(frame: NSRect(origin: .zero, size: size), message: message)
    }

    private init(message: String) {
        let size = NSSize(width: 200, height: 32)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver + 3
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let toastView = ToastContentView(frame: NSRect(origin: .zero, size: size), message: message)
        contentView = toastView
    }
}

private class ToastContentView: NSView {
    private let message: String

    init(frame: NSRect, message: String) {
        self.message = message
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        AdaptiveChrome.floatingBackground.setFill()
        path.fill()

        AdaptiveChrome.border.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ]
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        var wrapped = attrs
        wrapped[.paragraphStyle] = paragraph
        (message as NSString).draw(with: bounds.insetBy(dx: 12, dy: 8),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: wrapped)
    }
}
