import AppKit
import XCTest
@testable import capcap

@MainActor
final class ClipboardCommandTapTests: XCTestCase {
    func testCopyRequiresAnUnaccompaniedPressAndReleaseInEditor() throws {
        var editorReady = false
        var copies = 0
        let monitor = KeyMonitor(onTrigger: { _ in }, onCountdownTrigger: {},
                                 canCopyOnCommandTap: { editorReady },
                                 onCommandTap: { copies += 1 })
        let event = try XCTUnwrap(CGEvent(source: nil))
        func send(_ type: CGEventType, _ flags: CGEventFlags = []) {
            event.flags = flags
            monitor.handleTappedEvent(type: type, event: event)
        }

        send(.flagsChanged, .maskCommand)
        editorReady = true
        send(.flagsChanged)
        XCTAssertEqual(copies, 0)

        for interruption in [CGEventType.keyDown, .leftMouseDown] {
            send(.flagsChanged, .maskCommand)
            send(interruption, .maskCommand)
            send(.flagsChanged)
            XCTAssertEqual(copies, 0)
        }

        send(.flagsChanged, .maskCommand)
        send(.flagsChanged, [.maskCommand, .maskAlternate])
        send(.flagsChanged, .maskCommand)
        send(.flagsChanged)
        XCTAssertEqual(copies, 0)

        send(.flagsChanged, .maskCommand)
        XCTAssertEqual(copies, 0)
        send(.flagsChanged)
        XCTAssertEqual(copies, 1)
    }
}
