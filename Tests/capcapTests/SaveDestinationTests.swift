import Foundation
import XCTest
@testable import capcap

final class SaveDestinationTests: XCTestCase {
    func testDefaultDirectoriesShareCapcapFolderAndCustomPathsRemain() {
        let keys = ["screenshotSaveDirectory", "recordingSaveDirectory"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(Defaults.screenshotSaveDirectory, documents.appendingPathComponent("capcap/screenshots", isDirectory: true))
        XCTAssertEqual(Defaults.recordingSaveDirectory, documents.appendingPathComponent("capcap/record", isDirectory: true))
        let custom = FileManager.default.temporaryDirectory.appendingPathComponent("custom-capcap-output", isDirectory: true)
        Defaults.screenshotSaveDirectory = custom
        Defaults.recordingSaveDirectory = custom
        XCTAssertEqual(Defaults.screenshotSaveDirectory, custom.standardizedFileURL)
        XCTAssertEqual(Defaults.recordingSaveDirectory, custom.standardizedFileURL)
    }

    func testNestedDirectoriesAreCreatedAndExistingOutputsPreserved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (folder, filename) in [("screenshots", "capture.png"), ("record", "capture.mp4")] {
            let directory = root.appendingPathComponent("capcap/" + folder, isDirectory: true)
            let first = try SaveDestination.uniqueFile(in: directory, fileName: filename)
            let payload = Data("existing-output".utf8)
            try payload.write(to: first)
            let next = try SaveDestination.uniqueFile(in: directory, fileName: filename)
            XCTAssertNotEqual(first, next)
            XCTAssertEqual(next.deletingLastPathComponent(), directory)
            XCTAssertEqual(try Data(contentsOf: first), payload)
        }
    }
}
