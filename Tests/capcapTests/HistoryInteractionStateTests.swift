import AppKit
import XCTest
@testable import capcap

@MainActor
final class HistoryInteractionStateTests: XCTestCase {
    func testPositionFollowsEntryAcrossInsertionsAndFallsBackAfterDeletion() {
        let bookmark = HistoryBrowsePosition(entryID: "42", index: 42, fraction: 0.4)
        let ids = (0..<100).map(String.init)
        XCTAssertEqual(bookmark.resolvedIndex(in: ["new"] + ids), 43)
        XCTAssertEqual(bookmark.resolvedIndex(in: ids.filter { $0 != "42" }), 42)
        XCTAssertEqual(bookmark.resolvedIndex(in: ["a", "b"]), 1)
        XCTAssertNil(bookmark.resolvedIndex(in: []))
        let memory = HistoryBrowseMemory()
        let source = NSObject()
        memory.remember(bookmark, for: .screenshots, source: source)
        XCTAssertNil(memory[.text])
        XCTAssertEqual(memory[.screenshots]?.fraction, 0.4)
    }

    func testPanelsShareFilterAndNewPanelsInheritIt() {
        _ = NSApplication.shared
        let memory = HistoryBrowseMemory()
        let first = HistoryPanelContentView(presentation: .notch, browseMemory: memory)
        let second = HistoryPanelContentView(presentation: .notch, browseMemory: memory)
        first.selectFilter(.text)
        XCTAssertEqual(second.selectedFilter, .text)
        second.selectFilter(.files)
        XCTAssertEqual(first.selectedFilter, .files)
        let reopened = HistoryPanelContentView(presentation: .dialog, browseMemory: memory)
        XCTAssertEqual(reopened.selectedFilter, .files)
    }

    func testPositionsAreSharedAcrossSourcesAndDuplicateUpdatesDoNotNotify() {
        let memory = HistoryBrowseMemory()
        let first = NSObject(), second = NSObject()
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(
            forName: HistoryBrowseMemory.didChange, object: memory, queue: nil) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        let position = HistoryBrowsePosition(entryID: "42", index: 42, fraction: 0.4)
        memory.remember(position, for: .files, source: first)
        memory.remember(position, for: .files, source: second)
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(memory[.files], position)
        let next = HistoryBrowsePosition(entryID: "50", index: 50, fraction: 0.2)
        memory.remember(next, for: .files, source: second)
        XCTAssertEqual(memory[.files], next)
        memory.select(.text, source: first)
        memory.select(.files, source: second)
        XCTAssertEqual(memory[.files], next)
    }

    func testDifferentWidthPanelsMirrorScrollingAndRestoreAfterReopening() async throws {
        _ = NSApplication.shared
        let memory = HistoryBrowseMemory()
        let entries = (0..<200).map { index in
            HistoryEntry(fileURL: URL(fileURLWithPath: "/tmp/capcap-sync-fixture-\(index)"),
                         createdAt: .distantPast, kind: .color(hex: "#12AB34"), cloudURL: nil)
        }
        let first = HistoryPanelContentView(presentation: .notch, browseMemory: memory, entriesProvider: { entries })
        let second = HistoryPanelContentView(presentation: .notch, browseMemory: memory, entriesProvider: { entries })
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
        func waitFor(_ condition: () -> Bool) async throws {
            for _ in 0..<100 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTFail("Panels did not reach the expected shared browse position")
        }
        try await waitFor { firstCollection.numberOfItems(inSection: 0) >= 30 && secondCollection.numberOfItems(inSection: 0) >= 30 }
        // Allow the initial asynchronous anchor restoration to finish.
        await Task.yield()
        firstScroll.contentView.scroll(to: NSPoint(x: 1100, y: 0))
        try await waitFor { abs(secondScroll.contentView.bounds.minX - 1100) < 1 }
        second.setActive(false)
        firstScroll.contentView.scroll(to: NSPoint(x: 1700, y: 0))
        second.setActive(true)
        try await waitFor { abs(secondScroll.contentView.bounds.minX - 1700) < 1 }
        XCTAssertEqual(firstScroll.contentView.bounds.minX, 1700, accuracy: 1)
        // A bookmark beyond the first page must materialize on both screens.
        memory.remember(HistoryBrowsePosition(entryID: entries[125].fileURL.standardizedFileURL.path,
                                             index: 125, fraction: 0.25), for: .all, source: NSObject())
        try await waitFor { firstCollection.numberOfItems(inSection: 0) > 125 && secondCollection.numberOfItems(inSection: 0) > 125 }
        try await waitFor { firstScroll.contentView.bounds.minX > 10000 && abs(firstScroll.contentView.bounds.minX - secondScroll.contentView.bounds.minX) < 1 }
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
