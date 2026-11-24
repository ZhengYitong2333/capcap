import AppKit
import XCTest
@testable import capcap

@MainActor
final class HistoryInteractionStateTests: XCTestCase {
    func testPanelsShareFilterAndNewPanelsInheritIt() {
        _ = NSApplication.shared
        let memory = HistoryFilterState()
        let first = HistoryPanelContentView(presentation: .notch, filterState: memory)
        let second = HistoryPanelContentView(presentation: .notch, filterState: memory)
        first.selectFilter(.text)
        XCTAssertEqual(second.selectedFilter, .text)
        second.selectFilter(.files)
        XCTAssertEqual(first.selectedFilter, .files)
        let reopened = HistoryPanelContentView(presentation: .dialog, filterState: memory)
        XCTAssertEqual(reopened.selectedFilter, .files)
    }

    func testPanelsStartAtNewestOnOpeningAndFilterChanges() async throws {
        _ = NSApplication.shared
        let memory = HistoryFilterState()
        let entries = (0..<200).map { index in
            HistoryEntry(fileURL: URL(fileURLWithPath: "/tmp/capcap-sync-fixture-\(index)"),
                         createdAt: .distantPast, kind: .color(hex: "#12AB34"), cloudURL: nil)
        }
        let first = HistoryPanelContentView(presentation: .notch, filterState: memory, entriesProvider: { entries })
        let second = HistoryPanelContentView(presentation: .notch, filterState: memory, entriesProvider: { entries })
        let windows = [first, second].enumerated().map { index, view in
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: index == 0 ? 860 : 1400, height: 295),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            view.setActive(true)
            return window
        }
        defer {
            first.setActive(false)
            second.setActive(false)
            _ = windows
        }
        func collection(in view: NSView) -> NSCollectionView? {
            if let collection = view as? NSCollectionView { return collection }
            return view.subviews.lazy.compactMap { collection(in: $0) }.first
        }
        let firstCollection = try XCTUnwrap(collection(in: first))
        let secondCollection = try XCTUnwrap(collection(in: second))
        let firstScroll = try XCTUnwrap(firstCollection.enclosingScrollView)
        let secondScroll = try XCTUnwrap(secondCollection.enclosingScrollView)
        func waitFor(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
            for _ in 0..<100 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTFail("Panels did not reach the expected shared browse position: first=\(firstScroll.contentView.bounds.minX), second=\(secondScroll.contentView.bounds.minX), filters=\(first.selectedFilter)/\(second.selectedFilter)", file: file, line: line)
        }
        try await waitFor { firstCollection.numberOfItems(inSection: 0) >= 30 && secondCollection.numberOfItems(inSection: 0) >= 30 }
        // Allow the initial asynchronous anchor restoration to finish.
        await Task.yield()
        firstScroll.contentView.scroll(to: NSPoint(x: 1100, y: 0))
        secondScroll.contentView.scroll(to: NSPoint(x: 1700, y: 0))
        XCTAssertGreaterThan(firstScroll.contentView.bounds.minX, 1000)
        XCTAssertGreaterThan(secondScroll.contentView.bounds.minX, 1000)
        first.setActive(false)
        first.setActive(true)
        try await waitFor { abs(firstScroll.contentView.bounds.minX) < 1 && abs(secondScroll.contentView.bounds.minX) < 1 }
        memory.noteAddition(.colors)
        XCTAssertEqual(first.selectedFilter, .all)
        first.setActive(false)
        first.setActive(true)
        try await waitFor { first.selectedFilter == .colors && second.selectedFilter == .colors &&
            abs(firstScroll.contentView.bounds.minX) < 1 && abs(secondScroll.contentView.bounds.minX) < 1 }
        firstScroll.contentView.scroll(to: NSPoint(x: 1100, y: 0))
        secondScroll.contentView.scroll(to: NSPoint(x: 1700, y: 0))
        XCTAssertGreaterThan(firstScroll.contentView.bounds.minX, 1000)
        // A new item in the already-selected category also returns both panels to the start.
        memory.noteAddition(.colors)
        second.setActive(false)
        second.setActive(true)
        try await waitFor { abs(firstScroll.contentView.bounds.minX) < 1 && abs(secondScroll.contentView.bounds.minX) < 1 }
        firstScroll.contentView.scroll(to: NSPoint(x: 1100, y: 0))
        first.selectFilter(.all)
        try await waitFor { first.selectedFilter == .all && second.selectedFilter == .all &&
            abs(firstScroll.contentView.bounds.minX) < 1 && abs(secondScroll.contentView.bounds.minX) < 1 }
        first.selectFilter(.colors)
        try await waitFor { first.selectedFilter == .colors && second.selectedFilter == .colors &&
            abs(firstScroll.contentView.bounds.minX) < 1 && abs(secondScroll.contentView.bounds.minX) < 1 }

    }

    func testNewContentChoosesItsCategoryOnlyOnNextOpening() {
        let memory = HistoryFilterState()
        let source = NSObject()
        for category: HistoryPanelFilter in [.screenshots, .text, .files, .colors, .gif, .mp4] {
            memory.select(.favorites, source: source)
            memory.noteAddition(category)
            XCTAssertEqual(memory.selectedFilter, .favorites, "An open panel must not jump on insertion")
            XCTAssertTrue(memory.prepareForOpening(source: source))
            XCTAssertEqual(memory.selectedFilter, category)
        }
    }

    func testLatestAdditionWinsAndOrdinaryUpdatesKeepTheCategory() {
        let memory = HistoryFilterState()
        let first = NSObject(), second = NSObject()
        memory.noteAddition(.text)
        memory.noteAddition(.gif)
        XCTAssertTrue(memory.prepareForOpening(source: first))
        XCTAssertEqual(memory.selectedFilter, .gif)
        XCTAssertFalse(memory.prepareForOpening(source: second))
        XCTAssertEqual(memory.selectedFilter, .gif)
        memory.select(.favorites, source: first)
        NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
        XCTAssertFalse(memory.prepareForOpening(source: second))
        XCTAssertEqual(memory.selectedFilter, .favorites, "Ordinary history updates must not trigger category selection")
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
