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
