import AppKit
import XCTest
@testable import capcap

@MainActor
final class ToastFeedbackTests: XCTestCase {
    override func tearDown() { ToastWindow.dismiss(); super.tearDown() }

    func testSameOperationReusesWindowAndOldOperationCannotDismissIt() throws {
        _ = NSApplication.shared
        ToastWindow.show(message: "First", duration: 10, operationID: "save-A")
        let first = try XCTUnwrap(ToastWindow.captureExcludedWindowNumbers.first)
        ToastWindow.show(message: "Updated", duration: 10, operationID: "save-A")
        XCTAssertEqual(ToastWindow.captureExcludedWindowNumbers, [first])
        ToastWindow.show(message: "Copy", duration: 10, operationID: "copy-B")
        let second = ToastWindow.captureExcludedWindowNumbers
        ToastWindow.dismiss(operationID: "save-A")
        XCTAssertEqual(ToastWindow.captureExcludedWindowNumbers, second)
        ToastWindow.dismiss(operationID: "copy-B")
        XCTAssertTrue(ToastWindow.captureExcludedWindowNumbers.isEmpty)
    }

    func testLongErrorWrapsAndStaysOnSourceScreen() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        ToastWindow.show(message: String(repeating: "Could not save screenshot in this directory ", count: 8),
                         on: screen, topAnchor: NSPoint(x: screen.visibleFrame.maxX, y: screen.visibleFrame.minY), duration: 10)
        let id = try XCTUnwrap(ToastWindow.captureExcludedWindowNumbers.first)
        let window = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == Int(id) })
        XCTAssertLessThanOrEqual(window.frame.width, 420)
        XCTAssertGreaterThan(window.frame.height, 32)
        XCTAssertTrue(screen.visibleFrame.contains(window.frame))
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.isKeyWindow)
    }
}
