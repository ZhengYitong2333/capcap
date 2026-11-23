import AppKit

enum HistoryTextDrag {
    /// Publish text itself, never the history cache file's URL. This pasteboard
    /// belongs to the drag session and does not replace the general clipboard.
    static func pasteboardItem(for text: String) -> NSPasteboardItem? {
        guard !text.isEmpty else { return nil }
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        return item
    }

    static func preview(for text: String) -> NSImage {
        NSImage(size: NSSize(width: 220, height: 88), flipped: false) { rect in
            NSColor(calibratedWhite: 0.16, alpha: 0.96).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            // Only the visual preview is shortened; the payload remains exact.
            (String(text.prefix(256)) as NSString).draw(
                with: rect.insetBy(dx: 12, dy: 10), options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white,
                             .paragraphStyle: paragraph])
            return true
        }
    }
}
