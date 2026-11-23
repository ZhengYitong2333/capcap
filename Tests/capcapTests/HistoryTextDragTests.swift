import AppKit
import XCTest
@testable import capcap

@MainActor
final class HistoryTextDragTests: XCTestCase {
    func testTextFieldReceivesExactUnicodeMultilineTextInsteadOfCacheFile() throws {
        _ = NSApplication.shared
        let text = "  第一行 🐱\nsecond\tline\r\n最后一行  "
        let item = try XCTUnwrap(HistoryTextDrag.pasteboardItem(for: text))
        XCTAssertEqual(item.types, [.string])
        XCTAssertNil(item.string(forType: .fileURL))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let destination = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertTrue(destination.readSelection(from: pasteboard, type: .string))
        XCTAssertEqual(destination.string, text)
    }

    func testLongPayloadIsNotTruncatedAndEmptyTextCannotStartDrag() throws {
        let text = String(repeating: "多行内容\n", count: 10000)
        let item = try XCTUnwrap(HistoryTextDrag.pasteboardItem(for: text))
        XCTAssertEqual(item.string(forType: .string), text)
        XCTAssertEqual(HistoryTextDrag.preview(for: text).size, NSSize(width: 220, height: 88))
        XCTAssertNil(HistoryTextDrag.pasteboardItem(for: ""))
        XCTAssertEqual(HistoryTextDrag.pasteboardItem(for: "\n ")?.string(forType: .string), "\n ")
    }
}
