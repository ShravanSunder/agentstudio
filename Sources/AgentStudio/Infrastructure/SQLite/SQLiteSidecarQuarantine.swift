import Foundation

enum SQLiteSidecarQuarantine {
    struct Result: Sendable, Equatable {
        let quarantinedFilenames: [String]
        let failedFilenames: [String]

        var succeeded: Bool {
            !quarantinedFilenames.isEmpty && failedFilenames.isEmpty
        }

        var recoveryFilename: String? {
            guard !quarantinedFilenames.isEmpty else { return nil }
            return quarantinedFilenames.joined(separator: ", ")
        }
    }

    static func quarantine(databaseURL: URL, date: Date = Date()) -> Result {
        let timestamp = ISO8601DateFormatter().string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        var quarantinedFilenames: [String] = []
        var failedFilenames: [String] = []

        for sourceURL in sidecarURLs(for: databaseURL) where FileManager.default.fileExists(atPath: sourceURL.path) {
            let destinationURL = sourceURL.deletingLastPathComponent()
                .appending(path: "\(sourceURL.lastPathComponent).corrupt-\(timestamp)")
            do {
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                quarantinedFilenames.append(destinationURL.lastPathComponent)
            } catch {
                failedFilenames.append(sourceURL.lastPathComponent)
            }
        }

        return Result(
            quarantinedFilenames: quarantinedFilenames,
            failedFilenames: failedFilenames
        )
    }

    private static func sidecarURLs(for databaseURL: URL) -> [URL] {
        [
            databaseURL,
            URL(fileURLWithPath: "\(databaseURL.path)-wal"),
            URL(fileURLWithPath: "\(databaseURL.path)-shm"),
        ]
    }
}
