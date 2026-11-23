import XCTest
@testable import capcap

final class HistoryPreviewLoadGateTests: XCTestCase {
    func testPixelMovementWithinSameCardsDoesNotRescheduleLoading() {
        var gate = HistoryPreviewLoadGate()
        let visible = HistoryPreviewSchedule(range: 30...35, forward: true, pixelSize: 400, generation: 1)
        var visibleLoads = 0
        var prefetchLoads = 0
        for _ in 0..<1000 {
            let result = gate.update(visible, force: false)
            if result.visible { visibleLoads += 1 }
            if result.prefetch { prefetchLoads += 1 }
        }
        XCTAssertEqual(visibleLoads, 1)
        XCTAssertEqual(prefetchLoads, 1)
        let reversed = gate.update(HistoryPreviewSchedule(range: 30...35, forward: false, pixelSize: 400, generation: 1), force: false)
        XCTAssertFalse(reversed.visible)
        XCTAssertTrue(reversed.prefetch)
    }

    func testPaginationDataAndScreenScaleChangesInvalidateLoading() {
        var gate = HistoryPreviewLoadGate()
        for signature in [
            HistoryPreviewSchedule(range: 25...29, forward: true, pixelSize: 400, generation: 1),
            HistoryPreviewSchedule(range: 25...30, forward: true, pixelSize: 400, generation: 1),
            HistoryPreviewSchedule(range: 25...30, forward: true, pixelSize: 800, generation: 1),
            HistoryPreviewSchedule(range: 25...30, forward: true, pixelSize: 800, generation: 2)
        ] {
            let result = gate.update(signature, force: false)
            XCTAssertTrue(result.visible)
            XCTAssertTrue(result.prefetch)
        }
        gate.reset()
        let result = gate.update(HistoryPreviewSchedule(range: 25...30, forward: true, pixelSize: 800, generation: 2), force: false)
        XCTAssertTrue(result.visible)
        XCTAssertTrue(result.prefetch)
    }
}
