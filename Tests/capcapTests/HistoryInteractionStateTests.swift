import AppKit
import XCTest
@testable import capcap

@MainActor
final class HistoryInteractionStateTests: XCTestCase {
    func testDwellWaitsAndLeavingCancelsSwitch() {
        let dwell = HistoryFilterDwell()
        var selected = "all"
        dwell.schedule { selected = "images" }
        let early = expectation(description: "Pointer leaves before the 200ms dwell")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(selected, "all")
            dwell.cancel()
            early.fulfill()
        }
        let settled = expectation(description: "Cancelled switch never fires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(selected, "all")
            settled.fulfill()
        }
        wait(for: [early, settled], timeout: 1)
    }

    func testOnlyLastHoveredFilterSwitchesAndClickCancelsPendingSwitch() {
        let dwell = HistoryFilterDwell()
        var selections: [String] = []
        dwell.schedule { selections.append("images") }
        dwell.schedule { selections.append("text") }
        let settled = expectation(description: "Latest filter wins")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(selections, ["text"])
            dwell.schedule { selections.append("files") }
            dwell.cancel()
            selections.append("favorites")
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1)
        let clicked = expectation(description: "Immediate click is not overwritten")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(selections, ["text", "favorites"])
            clicked.fulfill()
        }
        wait(for: [clicked], timeout: 1)
    }

    func testPositionFollowsEntryAcrossInsertionsAndFallsBackAfterDeletion() {
        let bookmark = HistoryBrowsePosition(entryID: "42", index: 42, fraction: 0.4)
        let ids = (0..<100).map(String.init)
        XCTAssertEqual(bookmark.resolvedIndex(in: ["new"] + ids), 43)
        XCTAssertEqual(bookmark.resolvedIndex(in: ids.filter { $0 != "42" }), 42)
        XCTAssertEqual(bookmark.resolvedIndex(in: ["a", "b"]), 1)
        XCTAssertNil(bookmark.resolvedIndex(in: []))
        let memory = HistoryBrowseMemory()
        memory["notch/1", .screenshots] = bookmark
        XCTAssertNil(memory["notch/2", .screenshots])
        XCTAssertNil(memory["notch/1", .text])
        XCTAssertNil(memory["dialog/1", .screenshots])
        XCTAssertEqual(memory["notch/1", .screenshots]?.fraction, 0.4)
    }

    func testSamplingStopsWhenUnneededAndSpeedsUpNearAnEntry() {
        XCTAssertEqual(HistorySamplingPolicy.interval(hasPanels: true, hoverEnabled: true, active: false, nearEntry: false, suspended: false), 0.1)
        XCTAssertEqual(HistorySamplingPolicy.interval(hasPanels: true, hoverEnabled: true, active: false, nearEntry: true, suspended: false), 0.035)
        XCTAssertEqual(HistorySamplingPolicy.interval(hasPanels: true, hoverEnabled: false, active: true, nearEntry: false, suspended: false), 0.035)
        XCTAssertNil(HistorySamplingPolicy.interval(hasPanels: true, hoverEnabled: false, active: false, nearEntry: true, suspended: false))
        XCTAssertNil(HistorySamplingPolicy.interval(hasPanels: true, hoverEnabled: true, active: true, nearEntry: true, suspended: true))
        XCTAssertNil(HistorySamplingPolicy.interval(hasPanels: false, hoverEnabled: true, active: false, nearEntry: false, suspended: false))
    }
}
