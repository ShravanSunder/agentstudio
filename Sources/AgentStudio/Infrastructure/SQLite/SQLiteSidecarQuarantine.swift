import Foundation
import os.log

private let sqliteSidecarQuarantineLogger = Logger(
    subsystem: "com.agentstudio",
    category: "SQLiteSidecarQuarantine"
)

enum SQLiteSidecarQuarantine {
    struct Result: Sendable, Equatable {
        enum Status: Sendable, Equatable {
            case moved
            case nothingToMove
            case partiallyMoved
            case failed
        }

        let quarantinedFilenames: [String]
        let failedFilenames: [String]

        var status: Status {
            if !failedFilenames.isEmpty {
                return quarantinedFilenames.isEmpty ? .failed : .partiallyMoved
            }
            return quarantinedFilenames.isEmpty ? .nothingToMove : .moved
        }

        var succeeded: Bool {
            switch status {
            case .moved, .nothingToMove:
                return true
            case .partiallyMoved, .failed:
                return false
            }
        }

        var recoveryFilename: String? {
            switch status {
            case .moved:
                return quarantinedFilenames.joined(separator: ", ")
            case .nothingToMove:
                return nil
            case .partiallyMoved:
                return
                    "quarantined: \(quarantinedFilenames.joined(separator: ", ")); failed: \(failedFilenames.joined(separator: ", "))"
            case .failed:
                return "failed: \(failedFilenames.joined(separator: ", "))"
            }
        }
    }

    static func quarantine(
        databaseURL: URL,
        date: Date = Date(),
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        moveItem: (URL, URL) throws -> Void = { sourceURL, destinationURL in
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        }
    ) -> Result {
        let timestamp = ISO8601DateFormatter().string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        var quarantinedFilenames: [String] = []
        var failedFilenames: [String] = []

        for sourceURL in sidecarURLs(for: databaseURL) where fileExists(sourceURL) {
            let destinationURL = sourceURL.deletingLastPathComponent()
                .appending(path: "\(sourceURL.lastPathComponent).corrupt-\(timestamp)")
            do {
                try moveItem(sourceURL, destinationURL)
                quarantinedFilenames.append(destinationURL.lastPathComponent)
            } catch {
                failedFilenames.append(sourceURL.lastPathComponent)
            }
        }

        if !failedFilenames.isEmpty {
            sqliteSidecarQuarantineLogger.error(
                "SQLite sidecar quarantine incomplete for \(databaseURL.lastPathComponent, privacy: .public); quarantined=\(quarantinedFilenames.joined(separator: ", "), privacy: .public); failed=\(failedFilenames.joined(separator: ", "), privacy: .public)"
            )
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
