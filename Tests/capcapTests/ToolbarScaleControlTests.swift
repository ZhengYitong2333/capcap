import AppKit
import XCTest
@testable import capcap

@MainActor
final class ToolbarScaleControlTests: XCTestCase {
    func testPlacedToolbarsUseNativePointBoundsAndRegenerateIcons() throws {
        _ = NSApplication.shared
        for orientation in [ToolbarView.Orientation.horizontal, .vertical] {
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 1200))
            let toolbar = ToolbarView(items: [.sizeControl, .pen], orientation: orientation)
            host.addSubview(toolbar)
            let button = try XCTUnwrap(toolbar.subviews.compactMap { $0 as? ToolButton }.first)
            let originalIconSize = try XCTUnwrap(button.image).size
            for scale: CGFloat in [2, 0.5, 1.5, 1] {
                let size = NSSize(width: toolbar.preferredSize.width * scale,
                                  height: toolbar.preferredSize.height * scale)
                toolbar.place(in: NSRect(origin: NSPoint(x: 20, y: 20), size: size))
                XCTAssertEqual(toolbar.bounds.size, toolbar.frame.size)
                XCTAssertEqual(button.bounds.size, button.frame.size)
                XCTAssertEqual(button.frame.width, ToolbarView.buttonSize * scale, accuracy: 0.01)
                let frameInHost = button.convert(button.bounds, to: host)
                XCTAssertEqual(frameInHost.size.width, button.bounds.width, accuracy: 0.01)
                let hit = host.hitTest(NSPoint(x: frameInHost.midX, y: frameInHost.midY))
                XCTAssertTrue(hit === button)
                let icon = try XCTUnwrap(button.image)
                if scale > 1 { XCTAssertGreaterThan(icon.size.height, originalIconSize.height) }
                if scale < 1 { XCTAssertLessThan(icon.size.height, originalIconSize.height) }
                if scale == 1 { XCTAssertEqual(icon.size, originalIconSize) }
            }
        }
    }

    func testSliderNormalizesScaleAndUpdatesBothToolbarOrientations() throws {
        try withSavedScale {
            Defaults.toolbarSizePercent = 100
            let popover = SizeControlPopoverView()
            let slider = try XCTUnwrap(popover.subviews.compactMap { $0 as? HUDSlider }.first)
            let horizontal = ToolbarView(items: [.sizeControl, .confirm], orientation: .horizontal)
            let vertical = ToolbarView(items: [.pen, .text], orientation: .vertical)
            let available = NSSize(width: 2000, height: 2000)
            let sizes = [horizontal, vertical].map { $0.scaledSize(fitting: available) }
            slider.doubleValue = 127
            XCTAssertTrue(slider.sendAction(slider.action, to: slider.target))
            XCTAssertEqual(Defaults.toolbarSizePercent, 125)
            XCTAssertEqual(slider.doubleValue, 125)
            for (toolbar, original) in zip([horizontal, vertical], sizes) {
                let scaled = toolbar.scaledSize(fitting: available)
                XCTAssertEqual(scaled.width, original.width * 1.25, accuracy: 0.01)
                XCTAssertEqual(scaled.height, original.height * 1.25, accuracy: 0.01)
            }
            let rightArrow = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: 124
            ))
            slider.keyDown(with: rightArrow)
            XCTAssertEqual(Defaults.toolbarSizePercent, 130)
        }
    }

    func testSettingsChangesRefreshOpenPopoverAndPresetsPersist() throws {
        try withSavedScale {
            let popover = SizeControlPopoverView()
            let slider = try XCTUnwrap(popover.subviews.compactMap { $0 as? HUDSlider }.first)
            Defaults.toolbarSizePercent = 50
            XCTAssertEqual(slider.doubleValue, 50)
            XCTAssertTrue(popover.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "50%" })
            let preset = try XCTUnwrap(popover.subviews.compactMap { $0 as? NSButton }.first { $0.title == "200%" })
            preset.performClick(nil)
            XCTAssertEqual(Defaults.toolbarSizePercent, 200)
            XCTAssertEqual(slider.doubleValue, 200)
            let reopened = SizeControlPopoverView()
            XCTAssertEqual(reopened.subviews.compactMap { $0 as? HUDSlider }.first?.doubleValue, 200)
        }
    }

    func testScaleClampsAtBoundsAndDoesNotNotifyForSameNormalizedValue() {
        withSavedScale {
            Defaults.toolbarSizePercent = 100
            let changed = expectation(description: "Only effective scale changes notify")
            changed.expectedFulfillmentCount = 2
            changed.assertForOverFulfill = true
            let observer = NotificationCenter.default.addObserver(forName: .toolbarSizeDidChange, object: nil, queue: nil) { _ in
                changed.fulfill()
            }
            defer { NotificationCenter.default.removeObserver(observer) }
            Defaults.toolbarSizePercent = -10
            XCTAssertEqual(Defaults.toolbarSizePercent, 50)
            Defaults.toolbarSizePercent = 51
            Defaults.toolbarSizePercent = 500
            XCTAssertEqual(Defaults.toolbarSizePercent, 200)
            Defaults.toolbarSizePercent = 201
            wait(for: [changed], timeout: 1)
        }
    }

    private func withSavedScale(_ body: () throws -> Void) rethrows {
        _ = NSApplication.shared
        let key = "editor.toolbarSizePercent"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        try body()
    }
}
