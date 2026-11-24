import Foundation
import XCTest
@testable import capcap

final class HistoryRecordingProvenanceTests: XCTestCase {
    func testOnlyRecordingWithMatchingOriginalIdentityCanBeDeletedOutsideCache() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        func file(_ name: String) throws -> URL {
            let url = dir.appendingPathComponent(name)
            try Data([1, 2]).write(to: url)
            return url
        }
        let recorded = try file("recorded.mp4")
        let older = try file("capcap-older.gif")
        let replaced = try file("replaced.mp4")
        let favorite = try file("favorite.gif")
        HistoryRecordingProvenance.mark(recorded)
        HistoryRecordingProvenance.mark(replaced)
        HistoryRecordingProvenance.mark(favorite)
        XCTAssertTrue(HistoryManager.setFavorite(true, on: favorite))
        let copy = dir.appendingPathComponent("copy.mp4")
        try fm.copyItem(at: recorded, to: copy)
        let hardlink = dir.appendingPathComponent("alias.mp4")
        try fm.linkItem(at: recorded, to: hardlink)
        let symlink = dir.appendingPathComponent("link.mp4")
        try fm.createSymbolicLink(at: symlink, withDestinationURL: older)
        try Data([3, 4]).write(to: replaced, options: .atomic)
        XCTAssertTrue(HistoryRecordingProvenance.owns(recorded))
        let result = HistoryManager.removeUnfavoritedEntries([older, replaced, copy, hardlink, symlink, favorite, recorded])
        XCTAssertEqual(result.removed, [recorded])
        XCTAssertEqual(result.favorites, [favorite])
        XCTAssertEqual(result.skipped, [older, replaced, copy, hardlink, symlink])
        for url in result.kept { XCTAssertTrue(fm.fileExists(atPath: url.path)) }
        XCTAssertFalse(fm.fileExists(atPath: recorded.path))
    }

    func testCacheDirectoryAndFileSymlinksCannotGrantDeletion() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let real = dir.appendingPathComponent("recordings", isDirectory: true)
        let cache = dir.appendingPathComponent("history", isDirectory: true)
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let protected = real.appendingPathComponent("original.mp4")
        try Data([1]).write(to: protected)
        let link = cache.appendingPathComponent("link.mp4")
        try fm.createSymbolicLink(at: link, withDestinationURL: protected)
        let cacheLink = dir.appendingPathComponent("redirect", isDirectory: true)
        try fm.createSymbolicLink(at: cacheLink, withDestinationURL: real)
        let throughLink = cacheLink.appendingPathComponent("original.mp4")
        HistoryRecordingProvenance.mark(protected)
        XCTAssertTrue(HistoryRecordingProvenance.owns(protected))
        XCTAssertEqual(HistoryManager.removeUnfavoritedEntries([link], managedCache: cache).skipped, [link])
        XCTAssertEqual(HistoryManager.removeUnfavoritedEntries([throughLink], managedCache: cacheLink).skipped, [throughLink])
        XCTAssertTrue(fm.fileExists(atPath: protected.path))
    }
}
