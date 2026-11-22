import AppKit
import UniformTypeIdentifiers

/// What a hovered history card can preview without activating the app or
/// swapping the user's Space.
enum HistoryHoverPreviewContent {
    case image(URL)
    case videoFrame(URL)
    case quickLook(HistoryFileReferences)
    case text(HistoryFileReferences.Reference)
}

/// Decides which history entries get a hover preview and which loader path
/// they use. Unsupported file types keep the current card-only presentation.
enum HistoryHoverPreviewEligibility {
    private static let officeTypeIdentifiers: Set<String> = [
        "org.openxmlformats.wordprocessingml.document",
        "com.microsoft.word.doc",
        "org.openxmlformats.spreadsheetml.sheet",
        "com.microsoft.excel.xls",
        "org.openxmlformats.presentationml.presentation",
        "com.microsoft.powerpoint.ppt",
    ]

    private static let officeExtensions: Set<String> = [
        "doc", "docx", "xls", "xlsx", "ppt", "pptx",
    ]

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "swift", "py", "js", "ts", "json", "yaml", "yml",
        "html", "css", "sh", "rs", "go", "c", "h", "cpp", "hpp", "java", "kt",
        "rb", "php", "sql", "toml", "xml", "log", "csv",
    ]

    static func content(for entry: HistoryEntry) -> HistoryHoverPreviewContent? {
        switch entry.kind {
        case .image:
            return .image(entry.fileURL)
        case .video:
            return .videoFrame(entry.fileURL)
        case .files(let files):
            // Multi-file cards have no single obvious subject to preview.
            guard files.references.count == 1,
                  let reference = files.references.first,
                  !reference.isDirectory else { return nil }
            return content(for: reference, files: files)
        case .text, .color:
            return nil
        }
    }

    private static func content(
        for reference: HistoryFileReferences.Reference,
        files: HistoryFileReferences
    ) -> HistoryHoverPreviewContent? {
        let pathExtension = (reference.path as NSString).pathExtension.lowercased()
        if officeExtensions.contains(pathExtension) {
            return .quickLook(files)
        }
        if let identifier = reference.typeIdentifier,
           officeTypeIdentifiers.contains(identifier) {
            return .quickLook(files)
        }

        let type = reference.typeIdentifier.flatMap { UTType($0) }
            ?? UTType(filenameExtension: pathExtension)
        if let type {
            if type.conforms(to: .pdf) {
                return .quickLook(files)
            }
            if type.conforms(to: .movie)
                || type.conforms(to: .video)
                || type.conforms(to: .audiovisualContent) {
                return .quickLook(files)
            }
            if type.conforms(to: .text) || type.conforms(to: .sourceCode) {
                return .text(reference)
            }
        }
        if textExtensions.contains(pathExtension) {
            return .text(reference)
        }
        return nil
    }
}

/// Reads a bounded text prefix off the main thread. The hover panel ignores
/// mouse events, so the preview is intentionally a non-scrollable excerpt.
final class HistoryHoverTextLoader {
    static let shared = HistoryHoverTextLoader()

    private static let maxBytes = 256 * 1024
    private static let maxCharacters = 4000

    private final class CachedText: NSObject {
        let text: String
        init(_ text: String) { self.text = text }
    }

    private let queue = DispatchQueue(label: "capcap.historyHoverText", qos: .utility)
    private let cache: NSCache<NSString, CachedText> = {
        let cache = NSCache<NSString, CachedText>()
        cache.countLimit = 24
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()

    private init() {}

    @discardableResult
    func load(
        reference: HistoryFileReferences.Reference,
        completion: @escaping (String?) -> Void
    ) -> HistoryImagePreviewRequest {
        let token = HistoryImagePreviewRequest()
        queue.async { [weak self] in
            guard let self, !token.isCancelled else { return }
            let text = self.read(reference: reference, token: token)
            guard !token.isCancelled else { return }
            DispatchQueue.main.async {
                guard !token.isCancelled else { return }
                completion(text)
            }
        }
        return token
    }

    private func read(
        reference: HistoryFileReferences.Reference,
        token: HistoryImagePreviewRequest
    ) -> String? {
        guard let url = reference.resolve() else { return nil }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = "\(url.path)#\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)#\(values?.fileSize ?? 0)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached.text
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: Self.maxBytes)) ?? Data()
        guard !data.isEmpty, !token.isCancelled,
              !data.contains(0) else { return nil }

        var text: String?
        var utf8Data = data
        for _ in 0..<4 {
            if let decoded = String(data: utf8Data, encoding: .utf8) {
                text = decoded
                break
            }
            guard utf8Data.count > 1 else { break }
            utf8Data.removeLast()
        }
        if text == nil {
            text = String(data: data, encoding: .isoLatin1)
        }
        guard var result = text else { return nil }
        if result.count > Self.maxCharacters {
            result = String(result.prefix(Self.maxCharacters))
        }
        cache.setObject(CachedText(result), forKey: key, cost: result.utf8.count)
        return result
    }
}

/// Borderless, non-activating preview window that follows the hovered card.
final class HistoryHoverPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
}

/// Owns the hover preview panel. One instance lives in the history content
/// view; `show` cancels any in-flight preview before starting the next.
final class HistoryHoverPreviewController {
    private static let imagePixelSize = 1600

    private let panel = HistoryHoverPreviewPanel()
    private let surface = AdaptiveChromeSurfaceView(style: .floating, cornerRadius: 12, borderWidth: 1)
    private let imageView = NSImageView()
    private let textScrollView = NSScrollView()
    private let textView = NSTextView()
    private let messageLabel = NSTextField(labelWithString: "")

    private weak var parentWindow: NSWindow?
    private var currentRequest: HistoryImagePreviewRequest?
    private var generation = 0
    private var anchorRectInScreen: NSRect = .zero

    init() {
        panel.contentView = surface
        surface.autoresizingMask = [.width, .height]

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.isHidden = true
        surface.addSubview(imageView)

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 2, height: 2)
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = []
        textView.textContainer?.widthTracksTextView = true

        textScrollView.documentView = textView
        textScrollView.drawsBackground = false
        textScrollView.hasVerticalScroller = false
        textScrollView.hasHorizontalScroller = false
        textScrollView.isHidden = true
        surface.addSubview(textScrollView)

        messageLabel.font = .systemFont(ofSize: 11, weight: .medium)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.isHidden = true
        surface.addSubview(messageLabel)
    }

    deinit {
        currentRequest?.cancel()
        panel.close()
    }

    func show(
        content: HistoryHoverPreviewContent,
        anchor: NSRect,
        parent: NSWindow
    ) {
        generation += 1
        let currentGeneration = generation
        currentRequest?.cancel()
        currentRequest = nil
        anchorRectInScreen = anchor
        attach(to: parent)

        switch content {
        case .image(let url):
            if let cached = HistoryImagePreviewLoader.shared.cachedPreview(
                url: url, pixelSize: Self.imagePixelSize
            ), let image = cached.cgImage {
                presentImage(image)
                return
            }
            waitForContent()
            currentRequest = HistoryImagePreviewLoader.shared.load(
                url: url, pixelSize: Self.imagePixelSize, priority: .visible
            ) { [weak self] preview in
                guard let self, currentGeneration == self.generation else { return }
                if let image = preview.cgImage {
                    self.presentImage(image)
                } else {
                    self.presentUnavailable()
                }
            }
        case .videoFrame(let url):
            if let cached = HistoryImagePreviewLoader.shared.cachedVideoFrame(
                url: url, pixelSize: Self.imagePixelSize
            ), let image = cached.cgImage {
                presentImage(image)
                return
            }
            waitForContent()
            currentRequest = HistoryImagePreviewLoader.shared.loadVideoFrame(
                url: url, pixelSize: Self.imagePixelSize, priority: .visible
            ) { [weak self] preview in
                guard let self, currentGeneration == self.generation else { return }
                if let image = preview.cgImage {
                    self.presentImage(image)
                } else {
                    self.presentUnavailable()
                }
            }
        case .quickLook(let files):
            waitForContent()
            currentRequest = HistoryFilePreviewLoader.shared.load(
                files: files, pixelSize: Self.imagePixelSize
            ) { [weak self] preview in
                guard let self, currentGeneration == self.generation else { return }
                if let image = preview.image {
                    self.presentImage(image)
                } else {
                    self.presentUnavailable()
                }
            }
        case .text(let reference):
            waitForContent()
            currentRequest = HistoryHoverTextLoader.shared.load(reference: reference) {
                [weak self] text in
                guard let self, currentGeneration == self.generation else { return }
                if let text, !text.isEmpty {
                    self.presentText(text)
                } else {
                    self.presentUnavailable()
                }
            }
        }
    }

    func hide() {
        generation += 1
        currentRequest?.cancel()
        currentRequest = nil
        if panel.isVisible {
            panel.orderOut(nil)
        }
        detach()
    }

    func close() {
        hide()
        panel.close()
    }

    private func attach(to parent: NSWindow) {
        if parentWindow === parent, panel.parent != nil {
            panel.level = parent.level + 1
            return
        }
        detach()
        parentWindow = parent
        panel.level = parent.level + 1
        parent.addChildWindow(panel, ordered: .above)
    }

    private func detach() {
        if panel.parent != nil {
            panel.parent?.removeChildWindow(panel)
        }
        parentWindow = nil
    }

    private func presentImage(_ image: CGImage) {
        hideTransientContent()
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        imageView.image = nsImage
        imageView.isHidden = false

        let maxSize = maximumPreviewSize()
        let aspect = CGFloat(image.width) / CGFloat(max(1, image.height))
        var width = maxSize.width
        var height = width / max(aspect, 0.01)
        if height > maxSize.height {
            height = maxSize.height
            width = height * aspect
        }
        let padding: CGFloat = 8
        let panelSize = NSSize(
            width: max(120, width + padding * 2),
            height: max(80, height + padding * 2)
        )
        imageView.frame = NSRect(origin: .zero, size: panelSize)
            .insetBy(dx: padding, dy: padding)
        layoutPanel(size: panelSize)
    }

    private func presentText(_ text: String) {
        hideTransientContent()
        textView.string = text
        textScrollView.isHidden = false

        let maxSize = maximumPreviewSize()
        let scale = CGFloat(Defaults.historyHoverPreviewSizePercent) / 100
        let panelSize = NSSize(
            width: min(560 * scale, maxSize.width),
            height: min(380 * scale, maxSize.height)
        )
        let inset: CGFloat = 10
        textScrollView.frame = NSRect(origin: .zero, size: panelSize)
            .insetBy(dx: inset, dy: inset)
        let contentSize = textScrollView.contentSize
        if let container = textView.textContainer {
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        }
        textView.frame = NSRect(
            x: 0,
            y: 0,
            width: contentSize.width,
            height: contentSize.height
        )
        layoutPanel(size: panelSize)
    }

    /// Keeps the panel off-screen until content is ready so a loading period
    /// never flashes an empty surface.
    private func waitForContent() {
        hideTransientContent()
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    private func presentUnavailable() {
        hideTransientContent()
        messageLabel.stringValue = L10n.historyFilePreviewUnavailable
        messageLabel.isHidden = false
        layoutMessagePanel()
    }

    private func hideTransientContent() {
        messageLabel.isHidden = true
        imageView.isHidden = true
        textScrollView.isHidden = true
    }

    private func layoutMessagePanel() {
        let size = NSSize(width: 236, height: 92)
        let labelWidth = size.width - 24
        let labelHeight = ceil(messageLabel.intrinsicContentSize.height)
        messageLabel.frame = NSRect(
            x: 12,
            y: (size.height - labelHeight) / 2,
            width: labelWidth,
            height: labelHeight
        )
        layoutPanel(size: size)
    }

    private func layoutPanel(size: NSSize) {
        panel.setContentSize(size)
        surface.frame = NSRect(origin: .zero, size: size)
        positionPanel(size: size)
        panel.orderFrontRegardless()
    }

    private func positionPanel(size: NSSize) {
        guard let screen = parentWindow?.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let gap: CGFloat = 12
        let anchor = anchorRectInScreen

        var origin = NSPoint(
            x: anchor.maxX + gap,
            y: anchor.midY - size.height / 2
        )
        if origin.x + size.width > visible.maxX {
            let left = anchor.minX - gap - size.width
            if left >= visible.minX {
                origin.x = left
            } else {
                origin.x = anchor.midX - size.width / 2
                let below = anchor.minY - gap - size.height
                if below >= visible.minY {
                    origin.y = below
                } else {
                    origin.y = anchor.maxY + gap
                }
            }
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func maximumPreviewSize() -> NSSize {
        let visible = (parentWindow?.screen ?? NSScreen.main)?.visibleFrame.size
            ?? NSSize(width: 1440, height: 900)
        let scale = CGFloat(Defaults.historyHoverPreviewSizePercent) / 100
        return NSSize(
            width: max(240, visible.width * 0.55 * scale),
            height: max(180, visible.height * 0.55 * scale)
        )
    }
}
