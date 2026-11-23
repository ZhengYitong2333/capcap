import AppKit
import XCTest
@testable import capcap

final class HistoryPanelAppearanceTests: XCTestCase {
    private let key = "historyPanelTransparencyPercent"
    private var originalValue: Any?

    override func setUp() {
        super.setUp()
        originalValue = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        if let originalValue {
            UserDefaults.standard.set(originalValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testUnsetPreferenceUsesDefaultButSavedZeroStaysOpaque() {
        XCTAssertEqual(Defaults.historyPanelTransparencyPercent, 15)
        Defaults.historyPanelTransparencyPercent = 0
        XCTAssertEqual(UserDefaults.standard.integer(forKey: key), 0)
        XCTAssertEqual(Defaults.historyPanelTransparencyPercent, 0)
        XCTAssertEqual(AppSurfaceAppearance.colors[0].alphaComponent, 1)
    }

    func testTransparencyChangesAlphaWithoutChangingBackgroundColor() throws {
        Defaults.historyPanelTransparencyPercent = 0
        let opaque = AppSurfaceAppearance.colors
        Defaults.historyPanelTransparencyPercent = 60
        let gradient = CAGradientLayer()
        AppSurfaceAppearance.update(gradient)
        let rendered = try XCTUnwrap(gradient.colors as? [CGColor])
        XCTAssertEqual(rendered.count, 3)
        for (before, after) in zip(opaque, rendered) {
            let original = try XCTUnwrap(before.usingColorSpace(.sRGB))
            let transparent = try XCTUnwrap(NSColor(cgColor: after)?.usingColorSpace(.sRGB))
            XCTAssertEqual(transparent.alphaComponent, 0.4, accuracy: 0.001)
            XCTAssertEqual(transparent.redComponent, original.redComponent, accuracy: 0.001)
            XCTAssertEqual(transparent.greenComponent, original.greenComponent, accuracy: 0.001)
            XCTAssertEqual(transparent.blueComponent, original.blueComponent, accuracy: 0.001)
        }
        Defaults.historyPanelTransparencyPercent = 100
        XCTAssertEqual(AppSurfaceAppearance.colors[0].alphaComponent, 0)
    }

    func testOutOfRangeValuesAreClampedAndUnchangedValuesDoNotNotify() {
        let changed = expectation(description: "Notify each effective appearance change")
        changed.expectedFulfillmentCount = 2
        changed.assertForOverFulfill = true
        let observer = NotificationCenter.default.addObserver(
            forName: .historyPanelAppearanceDidChange, object: nil, queue: nil
        ) { _ in changed.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }

        Defaults.historyPanelTransparencyPercent = -10
        XCTAssertEqual(Defaults.historyPanelTransparencyPercent, 0)
        Defaults.historyPanelTransparencyPercent = 0
        Defaults.historyPanelTransparencyPercent = 200
        XCTAssertEqual(Defaults.historyPanelTransparencyPercent, 100)
        Defaults.historyPanelTransparencyPercent = 100
        wait(for: [changed], timeout: 1)
    }
}
