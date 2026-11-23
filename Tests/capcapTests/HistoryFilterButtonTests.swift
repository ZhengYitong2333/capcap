import AppKit
import XCTest
@testable import capcap

@MainActor
final class HistoryFilterButtonTests: XCTestCase {
    func testEnteringFilterCallsSelectionImmediately() throws {
        _ = NSApplication.shared
        let button = HistoryPanelFilterButton(filter: .text)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 54, height: 26),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = button
        var selected = false
        button.onHover = { selected = true }
        let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, trackingNumber: 1, userData: nil))
        button.mouseEntered(with: event)
        XCTAssertTrue(selected, "Selection must happen before the event handler returns")
    }

    func testRoundedEdgesStayTransparentAndBottomEdgeHasNoGap() throws {
        _ = NSApplication.shared
        let button = HistoryPanelFilterButton(filter: .text)
        button.title = "文本"
        button.isSelected = true
        button.frame = NSRect(x: 0, y: 0, width: 54, height: 26)
        button.layoutSubtreeIfNeeded()
        for scale in [1, 2] {
            let width = 54 * scale, height = 26 * scale
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
                pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            bitmap.size = button.bounds.size
            button.cacheDisplay(in: button.bounds, to: bitmap)
            for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] {
                XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0.02)
            }
            // Every pixel along the straight bottom edge must have coverage.
            for x in (10 * scale)..<(44 * scale) {
                XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: x, y: height - 1)).alphaComponent, 0.2)
            }
            if let directory = ProcessInfo.processInfo.environment["CAPCAP_FILTER_RENDER_DIR"] {
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("filter-\(scale)x.png"))
            }
        }
    }
}
