import Foundation
import GRDB

enum SQLiteDatabaseFactory {
    static let defaultBusyTimeout: TimeInterval = 2

    static func makeInMemoryQueue(label: String = "AgentStudio.sqlite.memory") throws -> DatabaseQueue {
        try DatabaseQueue(named: nil, configuration: makeConfiguration(label: label))
    }

    static func makeFileBackedPool(
        at databaseURL: URL,
        label: String = "AgentStudio.sqlite.file"
    ) throws -> DatabasePool {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = makeConfiguration(label: label)
        configuration.journalMode = .wal
        return try DatabasePool(path: databaseURL.path, configuration: configuration)
    }

    static func makeConfiguration(label: String) -> Configuration {
        var configuration = Configuration()
        configuration.label = label
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(defaultBusyTimeout)
        return configuration
    }
}
