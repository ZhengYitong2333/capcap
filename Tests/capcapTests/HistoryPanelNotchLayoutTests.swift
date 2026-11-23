import XCTest
@testable import capcap

final class HistoryPanelNotchLayoutTests: XCTestCase {
    func testExternalScreenUsesThinStripInsteadOfNotchSizedBlock() {
        let geometry = HistoryNotchGeometry(
            notchWidth: 200, notchHeight: 24, screenWidth: 2560,
            notchLeadingX: 1180, hasPhysicalNotch: false
        )
        let strip = geometry.collapsedSize

        XCTAssertGreaterThanOrEqual(strip.width, 120)
        XCTAssertLessThanOrEqual(strip.height, 6)
        XCTAssertGreaterThanOrEqual(strip.width / strip.height, 20)
        XCTAssertLessThanOrEqual(strip.height + geometry.topInset, 12)
        XCTAssertGreaterThan(geometry.topInset, 0)
    }

    func testPhysicalNotchEntryKeepsHardwareDimensions() {
        let geometry = HistoryNotchGeometry(
            notchWidth: 210, notchHeight: 32, screenWidth: 1512,
            notchLeadingX: 651
        )

        XCTAssertEqual(geometry.collapsedSize, NSSize(width: 210, height: 32))
        XCTAssertEqual(geometry.topInset, 0)
    }

    func testFilterViewportEndsAtPhysicalNotchLeadingEdge() {
        let geometry = HistoryNotchGeometry(
            notchWidth: 210,
            notchHeight: 32,
            screenWidth: 1512,
            notchLeadingX: 651
        )
        let headerInset: CGFloat = 30
        let viewportWidth = geometry.filterViewportWidth(headerInset: headerInset)
        let expandedLeadingX = (geometry.screenWidth - geometry.expandedWidth) / 2
        let viewportTrailingX = expandedLeadingX + headerInset + viewportWidth

        XCTAssertLessThanOrEqual(viewportTrailingX, geometry.notchLeadingX)
        XCTAssertLessThan(geometry.notchLeadingX - viewportTrailingX, 1)
    }

    func testFilterViewportUsesActualNotchLeadingEdgeInsteadOfAssumingCenter() {
        let centered = HistoryNotchGeometry(
            notchWidth: 210,
            notchHeight: 32,
            screenWidth: 1512,
            notchLeadingX: 651
        )
        let shifted = HistoryNotchGeometry(
            notchWidth: 210,
            notchHeight: 32,
            screenWidth: 1512,
            notchLeadingX: 643
        )

        XCTAssertEqual(
            centered.filterViewportWidth(headerInset: 30)
                - shifted.filterViewportWidth(headerInset: 30),
            8
        )
    }

    func testSecondFilterFromLeadingEdgeSnapsViewportToLeadingEdge() {
        XCTAssertEqual(
            HistoryPanelFilterRevealPolicy.anchor(selectedIndex: 1, filterCount: 7),
            .leading
        )
    }

    func testSecondFilterFromTrailingEdgeSnapsViewportToTrailingEdge() {
        XCTAssertEqual(
            HistoryPanelFilterRevealPolicy.anchor(selectedIndex: 5, filterCount: 7),
            .trailing
        )
    }

    func testMiddleFiltersKeepNearestRevealBehavior() {
        XCTAssertEqual(
            HistoryPanelFilterRevealPolicy.anchor(selectedIndex: 3, filterCount: 7),
            .nearest
        )
    }

    func testOverlappingEdgeThresholdsKeepNearestRevealBehavior() {
        XCTAssertEqual(
            HistoryPanelFilterRevealPolicy.anchor(selectedIndex: 1, filterCount: 3),
            .nearest
        )
    }
}
