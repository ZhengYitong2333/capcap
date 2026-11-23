import AppKit
import Carbon
import XCTest
@testable import capcap

@MainActor
final class HistoryPreviewHotkeyOwnershipTests: XCTestCase {
    func testPreviousPanelCannotUnregisterNewPanelsSpaceHotkey() {
        let manager = HotkeyManager.shared
        let firstPanel = UUID()
        let secondPanel = UUID()
        defer {
            manager.unregisterHistoryPreview(owner: firstPanel)
            manager.unregisterHistoryPreview(owner: secondPanel)
        }

        XCTAssertTrue(manager.registerHistoryPreview(owner: firstPanel) {})
        XCTAssertTrue(manager.registerHistoryPreview(owner: secondPanel) {})

        // Models delayed collapse and subsequent destruction of the old panel.
        manager.unregisterHistoryPreview(owner: firstPanel)
        manager.unregisterHistoryPreview(owner: firstPanel)
        assertSpaceIsRegistered()

        manager.unregisterHistoryPreview(owner: secondPanel)
        assertSpaceIsAvailable()
    }

    func testOwnerCanReregisterAndRepeatedlyReleaseSpace() {
        let manager = HotkeyManager.shared
        let panel = UUID()
        defer { manager.unregisterHistoryPreview(owner: panel) }

        XCTAssertTrue(manager.registerHistoryPreview(owner: panel) {})
        XCTAssertTrue(manager.registerHistoryPreview(owner: panel) {})
        assertSpaceIsRegistered()

        manager.unregisterHistoryPreview(owner: panel)
        manager.unregisterHistoryPreview(owner: panel)
        assertSpaceIsAvailable()

        // Returning from preview must be able to acquire Space again.
        XCTAssertTrue(manager.registerHistoryPreview(owner: panel) {})
        assertSpaceIsRegistered()
    }

    func testFailedRegistrationDoesNotPreventLaterOwnerFromAcquiringSpace() throws {
        let manager = HotkeyManager.shared
        let failedPanel = UUID()
        let nextPanel = UUID()
        defer {
            manager.unregisterHistoryPreview(owner: failedPanel)
            manager.unregisterHistoryPreview(owner: nextPanel)
        }

        // Carbon permits only one registration per key combination in a process.
        let blocker = registerSpaceProbe()
        XCTAssertEqual(blocker.status, noErr)
        let blockerRef = try XCTUnwrap(blocker.ref)
        XCTAssertFalse(manager.registerHistoryPreview(owner: failedPanel) {})
        XCTAssertEqual(UnregisterEventHotKey(blockerRef), noErr)

        XCTAssertTrue(manager.registerHistoryPreview(owner: nextPanel) {})
        manager.unregisterHistoryPreview(owner: failedPanel)
        assertSpaceIsRegistered()
        manager.unregisterHistoryPreview(owner: nextPanel)
        assertSpaceIsAvailable()
    }

    // Probe the OS registration, not the manager's private ownership fields.
    // Always release a successful probe, including when an assertion fails.
    private func registerSpaceProbe() -> (status: OSStatus, ref: EventHotKeyRef?) {
        _ = NSApplication.shared
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Space), 0,
            EventHotKeyID(signature: OSType(0x5445_5354), id: 1),
            GetApplicationEventTarget(), 0, &ref
        )
        return (status, ref)
    }

    private func assertSpaceIsRegistered(file: StaticString = #filePath, line: UInt = #line) {
        let probe = registerSpaceProbe()
        defer { if let ref = probe.ref { UnregisterEventHotKey(ref) } }
        XCTAssertEqual(probe.status, OSStatus(eventHotKeyExistsErr), file: file, line: line)
    }

    private func assertSpaceIsAvailable(file: StaticString = #filePath, line: UInt = #line) {
        let probe = registerSpaceProbe()
        defer { if let ref = probe.ref { UnregisterEventHotKey(ref) } }
        XCTAssertEqual(probe.status, noErr, file: file, line: line)
        XCTAssertNotNil(probe.ref, file: file, line: line)
    }
}
