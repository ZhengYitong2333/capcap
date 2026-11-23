import AppKit

/// Main-thread ownership of a single save attempt; stale completions cannot
/// finish a cancelled session or a newer retry.
struct EditorSaveState {
    private(set) var operation: UUID?
    var isSaving: Bool { operation != nil }

    mutating func begin() -> UUID? {
        guard operation == nil else { return nil }
        let id = UUID()
        operation = id
        return id
    }

    func accepts(_ id: UUID) -> Bool { operation == id }

    @discardableResult
    mutating func finish(_ id: UUID) -> Bool {
        guard accepts(id) else { return false }
        operation = nil
        return true
    }

    mutating func cancel() { operation = nil }
}

/// Consume pointer input instead of forwarding unhandled events to SelectionView.
final class EditorSavingInputShield: NSView {
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}
