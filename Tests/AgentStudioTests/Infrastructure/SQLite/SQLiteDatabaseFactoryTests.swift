import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("SQLiteDatabaseFactoryTests")
struct SQLiteDatabaseFactoryTests {
    @Test("in-memory queue enables foreign keys")
    func inMemoryQueueEnablesForeignKeys() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        let foreignKeysEnabled = try databaseQueue.read { database in
            try Int.fetchOne(database, sql: "PRAGMA foreign_keys")
        }

        #expect(foreignKeysEnabled == 1)
    }

    @Test("connections use the Step 1 busy timeout")
    func connectionsUseStep1BusyTimeout() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        let busyTimeoutMilliseconds = try databaseQueue.read { database in
            try Int.fetchOne(database, sql: "PRAGMA busy_timeout")
        }

        #expect(busyTimeoutMilliseconds == 2000)
    }

    @Test("file-backed pool uses foreign keys and WAL")
    func fileBackedPoolUsesForeignKeysAndWAL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "sqlite-factory-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "core.sqlite")
        let databasePool = try SQLiteDatabaseFactory.makeFileBackedPool(at: databaseURL)

        let foreignKeysEnabled = try databasePool.read { database in
            try Int.fetchOne(database, sql: "PRAGMA foreign_keys")
        }
        let journalMode = try databasePool.read { database in
            try String.fetchOne(database, sql: "PRAGMA journal_mode")
        }
        let synchronousMode = try databasePool.read { database in
            try Int.fetchOne(database, sql: "PRAGMA synchronous")
        }
        let writerBusyTimeoutMilliseconds = try databasePool.write { database in
            try Int.fetchOne(database, sql: "PRAGMA busy_timeout")
        }

        #expect(foreignKeysEnabled == 1)
        #expect(journalMode?.lowercased() == "wal")
        #expect(synchronousMode == 1)
        #expect(writerBusyTimeoutMilliseconds == 2000)
    }

    @Test("byte-preserving startup reader sees committed WAL content without changing database files")
    func bytePreservingStartupReaderSeesCommittedWALWithoutChangingDatabaseFiles() throws {
        // Arrange
        let fixture = try SQLiteFactoryFileFixture.make()
        defer { fixture.remove() }
        try fixture.createCrashLeftWALDatabase()
        let durableFilesBeforeRead = try fixture.durableFileBytes()
        #expect(durableFilesBeforeRead.wal != .missing)
        #expect(durableFilesBeforeRead.sharedMemory != .missing)
        let mainDatabaseOnlyReader = try fixture.makeMainDatabaseOnlyImmutableReader()
        let mainDatabaseOnlyValue = try mainDatabaseOnlyReader.read { database in
            try String.fetchOne(database, sql: "SELECT value FROM startup_probe")
        }
        #expect(mainDatabaseOnlyValue == nil)

        // Act
        let startupReader = try SQLiteDatabaseFactory.makeBytePreservingStartupReader(at: fixture.databaseURL)
        let restoredValue = try startupReader.read { database in
            try String.fetchOne(database, sql: "SELECT value FROM startup_probe")
        }

        // Assert
        #expect(restoredValue == "committed-in-wal")
        let durableFilesAfterRead = try fixture.durableFileBytes()
        #expect(durableFilesAfterRead.database == durableFilesBeforeRead.database)
        #expect(durableFilesAfterRead.wal == durableFilesBeforeRead.wal)
        #expect(durableFilesAfterRead.sharedMemory == durableFilesBeforeRead.sharedMemory)
    }

    @Test("byte-preserving startup reader rejects a missing database without creating files")
    func bytePreservingStartupReaderRejectsMissingDatabaseWithoutCreatingFiles() throws {
        // Arrange
        let fixture = try SQLiteFactoryFileFixture.make()
        defer { fixture.remove() }
        let durableFilesBeforeRead = try fixture.durableFileBytes()

        // Act
        #expect(throws: (any Error).self) {
            _ = try SQLiteDatabaseFactory.makeBytePreservingStartupReader(at: fixture.databaseURL)
        }

        // Assert
        #expect(try fixture.durableFileBytes() == durableFilesBeforeRead)
    }

    @Test("byte-preserving startup reader rejects corrupt content without changing database files")
    func bytePreservingStartupReaderRejectsCorruptContentWithoutChangingDatabaseFiles() throws {
        // Arrange
        let fixture = try SQLiteFactoryFileFixture.make()
        defer { fixture.remove() }
        try Data("not a sqlite database".utf8).write(to: fixture.databaseURL)
        let durableFilesBeforeRead = try fixture.durableFileBytes()

        // Act
        #expect(throws: (any Error).self) {
            _ = try SQLiteDatabaseFactory.makeBytePreservingStartupReader(at: fixture.databaseURL)
        }

        // Assert
        #expect(try fixture.durableFileBytes() == durableFilesBeforeRead)
    }

    @Test("connection supports FTS5")
    func connectionSupportsFTS5() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        let matchingCount = try databaseQueue.write { database in
            try database.execute(sql: "CREATE VIRTUAL TABLE session_search_index USING fts5(body)")
            try database.execute(
                sql: "INSERT INTO session_search_index(body) VALUES (?)",
                arguments: ["sqlite workspace migration"]
            )
            return try Int.fetchOne(
                database,
                sql: "SELECT count(*) FROM session_search_index WHERE session_search_index MATCH ?",
                arguments: ["workspace"]
            )
        }

        #expect(matchingCount == 1)
    }

    @Test("JSON payload columns round trip as text")
    func jsonPayloadColumnsRoundTripAsText() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        let payload = #"{"kind":"terminal","provider":"zmx"}"#

        let restoredPayload = try databaseQueue.write { database in
            try database.execute(sql: "CREATE TABLE payload_probe (payload_json TEXT NOT NULL)")
            try database.execute(
                sql: "INSERT INTO payload_probe(payload_json) VALUES (?)",
                arguments: [payload]
            )
            return try String.fetchOne(database, sql: "SELECT payload_json FROM payload_probe")
        }

        #expect(restoredPayload == payload)
    }
}

private struct SQLiteFactoryFileFixture {
    enum FileBytes: Equatable {
        case missing
        case present(Data)
    }

    struct DurableFileBytes: Equatable {
        let database: FileBytes
        let wal: FileBytes
        let sharedMemory: FileBytes
    }

    let directoryURL: URL
    let databaseURL: URL

    static func make() throws -> Self {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "sqlite-factory-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return Self(
            directoryURL: directoryURL,
            databaseURL: directoryURL.appending(path: "startup database #1.sqlite")
        )
    }

    func durableFileBytes() throws -> DurableFileBytes {
        try DurableFileBytes(
            database: fileBytes(at: databaseURL),
            wal: fileBytes(at: URL(filePath: databaseURL.path + "-wal")),
            sharedMemory: fileBytes(at: URL(filePath: databaseURL.path + "-shm"))
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func createCrashLeftWALDatabase() throws {
        let process = Process()
        let standardError = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            """
            import os
            import sqlite3
            import sys

            connection = sqlite3.connect(sys.argv[1])
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute("PRAGMA wal_autocheckpoint=0")
            connection.execute("CREATE TABLE startup_probe (value TEXT NOT NULL)")
            connection.commit()
            connection.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchall()
            connection.execute(
                "INSERT INTO startup_probe(value) VALUES (?)",
                ("committed-in-wal",),
            )
            connection.commit()
            os._exit(0)
            """,
            databaseURL.path,
        ]
        process.standardError = standardError
        let terminationSignal = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminationSignal.signal() }
        try process.run()
        guard terminationSignal.wait(timeout: .now() + 10) == .success else {
            process.terminate()
            process.waitUntilExit()
            throw SQLiteFactoryFileFixtureError.fixtureProcessTimedOut
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
            throw SQLiteFactoryFileFixtureError.fixtureProcessFailed(
                status: process.terminationStatus,
                standardError: String(bytes: errorData, encoding: .utf8) ?? "<non-UTF8 stderr>"
            )
        }
    }

    func makeMainDatabaseOnlyImmutableReader() throws -> DatabaseQueue {
        var components = URLComponents(url: databaseURL.standardizedFileURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "immutable", value: "1")]
        let databaseURI = try #require(components?.string)
        var configuration = Configuration()
        configuration.readonly = true
        return try DatabaseQueue(path: databaseURI, configuration: configuration)
    }

    private func fileBytes(at fileURL: URL) throws -> FileBytes {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .missing
        }
        return try .present(Data(contentsOf: fileURL))
    }
}

private enum SQLiteFactoryFileFixtureError: Error {
    case fixtureProcessFailed(status: Int32, standardError: String)
    case fixtureProcessTimedOut
}
