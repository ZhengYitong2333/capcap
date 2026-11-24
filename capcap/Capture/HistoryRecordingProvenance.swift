import CryptoKit
import Darwin
import Foundation

/// Positive evidence that this file instance was saved by Capcap's recording producer.
/// Copying the extended attribute to a new file does not carry that evidence over.
enum HistoryRecordingProvenance {
    private static let attribute = "com.capcap.history.recording-origin"

    static func mark(_ url: URL) {
        withRegularFile(url) { fd, marker in
            _ = marker.withUnsafeBytes { bytes in
                fsetxattr(fd, attribute, bytes.baseAddress, bytes.count, 0, 0)
            }
        }
    }

    static func owns(_ url: URL) -> Bool {
        var matches = false
        withRegularFile(url) { fd, marker in
            var observed = [UInt8](repeating: 0, count: marker.count)
            let count = observed.withUnsafeMutableBytes { bytes in
                fgetxattr(fd, attribute, bytes.baseAddress, bytes.count, 0, 0)
            }
            matches = count == marker.count && observed == marker
        }
        return matches
    }

    private static func withRegularFile(_ url: URL, _ body: (Int32, [UInt8]) -> Void) {
        guard url.isFileURL else { return }
        let canonicalPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let pathDigest = SHA256.hash(data: Data(canonicalPath.utf8)).description
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            // A named pipe must not block history; a leaf symlink is never producer evidence.
            let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { return }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0,
                  info.st_mode & S_IFMT == S_IFREG else { return }
            let birth = info.st_birthtimespec
            let modified = info.st_mtimespec
            let marker = "v1:\(info.st_dev):\(info.st_ino):\(birth.tv_sec):\(birth.tv_nsec):"
                + "\(info.st_size):\(modified.tv_sec):\(modified.tv_nsec):\(pathDigest)"
            body(fd, Array(marker.utf8))
        }
    }
}
