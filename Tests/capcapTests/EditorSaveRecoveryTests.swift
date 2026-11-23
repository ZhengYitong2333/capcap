import AppKit
import XCTest
@testable import capcap

@MainActor
final class EditorSaveRecoveryTests: XCTestCase {
    func testRetryRejectsStaleCompletionsAndDuplicateSaves() throws {
        var state = EditorSaveState()
        let first = try XCTUnwrap(state.begin())
        XCTAssertNil(state.begin())
        XCTAssertTrue(state.finish(first))
        let retry = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.finish(first))
        XCTAssertTrue(state.accepts(retry))
        state.cancel()
        XCTAssertFalse(state.finish(retry))
    }

    func testWriteFailureKeepsEditorAndRetryCompletesOnce() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let host = SelectionView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        var completions = 0
        let controller = EditWindowController(captureRect: host.bounds, screen: screen,
            selectionRect: host.bounds, selectionViewRect: host.bounds, hostSelectionView: host,
            overrideBaseImage: image) { _ in completions += 1 }
        defer { controller.tearDown(); ToastWindow.dismiss() }
        controller.show()
        let originalSubviews = host.subviews
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let blocker = root.appendingPathComponent("file-not-directory")
        try Data([1]).write(to: blocker)
        controller.finishSave(image: image, destinationOverride: blocker.appendingPathComponent("failed.png"))
        waitUntil { !controller.saveState.isSaving }
        XCTAssertEqual(completions, 0)
        XCTAssertTrue(host.selectionInteractionEnabled)
        XCTAssertEqual(host.subviews, originalSubviews)
        let output = root.appendingPathComponent("retry.png")
        controller.finishSave(image: image, destinationOverride: output)
        controller.finishSave(image: image, destinationOverride: root.appendingPathComponent("duplicate.png"))
        waitUntil { completions == 1 }
        XCTAssertNotNil(NSImage(contentsOf: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("duplicate.png").path))
    }

    func testEncodingFailureAndCancelledCompletionDoNotCloseEditorAgain() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let host = SelectionView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        var completions = 0
        let controller = EditWindowController(captureRect: host.bounds, screen: screen,
            selectionRect: host.bounds, selectionViewRect: host.bounds, hostSelectionView: host) { _ in completions += 1 }
        defer { controller.tearDown(); ToastWindow.dismiss() }
        controller.finishSave(image: NSImage(size: .zero), destinationOverride: nil)
        XCTAssertFalse(controller.saveState.isSaving)
        XCTAssertEqual(completions, 0)
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            NSColor.blue.setFill(); rect.fill(); return true
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: output) }
        controller.finishSave(image: image, destinationOverride: output)
        controller.tearDown()
        let settled = expectation(description: "Cancelled encoder completion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertEqual(completions, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    private func waitUntil(_ condition: @escaping () -> Bool) {
        let done = expectation(description: "Save completion")
        let deadline = Date().addingTimeInterval(4)
        func poll() {
            if condition() { done.fulfill() }
            else if Date() >= deadline { XCTFail("Save did not finish"); done.fulfill() }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: poll) }
        }
        poll()
        wait(for: [done], timeout: 5)
    }
}
