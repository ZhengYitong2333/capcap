import AppKit
import XCTest
@testable import capcap

@MainActor
final class HistoryPanelResizeHandleTests: XCTestCase {
    func testExternalPanelResizeTargetsReachVisibleEdges() {
        _ = NSApplication.shared
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 262))
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        let left = makeHandle(.left, host: host)
        let right = makeHandle(.right, host: host)
        let bottomLeft = makeHandle(.bottomLeft, host: host)
        let bottomRight = makeHandle(.bottomRight, host: host)
        let bottom = makeHandle(.bottom, host: host)

        for handle in [left, right, bottomLeft, bottomRight, bottom] {
            handle.updateSideInset(0)
        }
        host.layoutSubtreeIfNeeded()

        XCTAssertTrue(host.hitTest(NSPoint(x: 1, y: 100)) === left)
        XCTAssertTrue(host.hitTest(NSPoint(x: 859, y: 100)) === right)
        XCTAssertTrue(host.hitTest(NSPoint(x: 15, y: 10)) === bottomLeft)
        XCTAssertTrue(host.hitTest(NSPoint(x: 845, y: 10)) === bottomRight)
        XCTAssertTrue(host.hitTest(NSPoint(x: 430, y: 1)) === bottom)
        XCTAssertTrue(host.hitTest(NSPoint(x: 430, y: 100)) === host)
        withExtendedLifetime(window) {}
    }

    func testInsetsUpdateWhenPanelGeometryChanges() {
        _ = NSApplication.shared
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 262))
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        let left = makeHandle(.left, host: host)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(left.frame.minX, 10, accuracy: 0.01)
        left.updateSideInset(0)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(left.frame.minX, 0, accuracy: 0.01)
        left.updateSideInset(10)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(left.frame.minX, 10, accuracy: 0.01)
        withExtendedLifetime(window) {}
    }

    private func makeHandle(_ edge: HistoryPanelResizeHandle.Edge, host: NSView) -> HistoryPanelResizeHandle {
        let handle = HistoryPanelResizeHandle(presentation: .notch, edge: edge)
        host.addSubview(handle)
        handle.pin(to: host)
        return handle
    }
}
