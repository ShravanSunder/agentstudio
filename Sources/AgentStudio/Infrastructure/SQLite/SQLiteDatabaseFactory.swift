import Foundation
import GRDB

enum SQLiteDatabaseFactory {
    enum FactoryError: Error, Equatable {
        case bytePreservingStartupReaderRequiresFileURL
        case invalidBytePreservingStartupReaderURL
    }

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

    static func makeBytePreservingStartupReader(
        at databaseURL: URL,
        label: String = "AgentStudio.sqlite.byte-preserving-startup-reader"
    ) throws -> DatabaseQueue {
        guard databaseURL.isFileURL else {
            throw FactoryError.bytePreservingStartupReaderRequiresFileURL
        }
        var databaseURIComponents = URLComponents(
            url: databaseURL.standardizedFileURL,
            resolvingAgainstBaseURL: false
        )
        databaseURIComponents?.queryItems = [
            URLQueryItem(name: "mode", value: "ro"),
            URLQueryItem(name: "readonly_shm", value: "1"),
        ]
        guard let databaseURI = databaseURIComponents?.string else {
            throw FactoryError.invalidBytePreservingStartupReaderURL
        }

        var configuration = makeConfiguration(label: label)
        configuration.readonly = true
        return try DatabaseQueue(path: databaseURI, configuration: configuration)
    }

    static func makeConfiguration(label: String) -> Configuration {
        var configuration = Configuration()
        configuration.label = label
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(defaultBusyTimeout)
        return configuration
    }
}
