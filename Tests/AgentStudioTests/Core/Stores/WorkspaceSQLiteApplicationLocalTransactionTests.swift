import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@Suite("Prepared application-local transactions")
struct WorkspaceSQLiteApplicationLocalTransactionTests {
    @Test("unprepared access fails without creating a database")
    func unpreparedAccessDoesNotOpenDatabase() async throws {
        let fixture = try ApplicationLocalTransactionFixture()
        defer { fixture.removeFiles() }
        let datastore = fixture.makeDatastore()

        await #expect(throws: WorkspaceSQLiteDatastoreError.databasesNotPrepared) {
            try await datastore.performApplicationLocalWrite { database in
                try database.execute(sql: "CREATE TABLE transaction_probe(value TEXT NOT NULL)")
            }
        }
        await #expect(throws: WorkspaceSQLiteDatastoreError.databasesNotPrepared) {
            try await datastore.performApplicationLocalRead { database in
                try Int.fetchOne(database, sql: "SELECT 1")
            }
        }

        #expect(!FileManager.default.fileExists(atPath: fixture.localDatabaseURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.coreDatabaseURL.path))
    }

    @Test("writes commit to the prepared application database and survive reopening")
    func committedValuesSurviveReopening() async throws {
        let fixture = try ApplicationLocalTransactionFixture()
        defer { fixture.removeFiles() }
        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Database preparation failed")
            return
        }

        // A subsequent app boot requires an initialized authoritative workspace.
        try await datastore.saveWorkspaceSnapshotBundle(
            .emptyFixture(id: UUIDv7.generate(), name: "Transaction proof")
        )
        try await datastore.performApplicationLocalWrite { database in
            try database.execute(sql: "CREATE TABLE transaction_probe(value TEXT NOT NULL)")
            try database.execute(sql: "INSERT INTO transaction_probe VALUES (?)", arguments: ["preserved"])
        }
        let committedValue = try await datastore.performApplicationLocalRead { database in
            try String.fetchOne(database, sql: "SELECT value FROM transaction_probe")
        }
        #expect(committedValue == "preserved")

        let reopenedDatastore = fixture.makeDatastore()
        let reopenedPreparation = await reopenedDatastore.prepareDatabasesForBoot()
        guard case .prepared = reopenedPreparation else {
            Issue.record("Database reopening failed: \(reopenedPreparation)")
            return
        }
        let reopenedValue = try await reopenedDatastore.performApplicationLocalRead { database in
            try String.fetchOne(database, sql: "SELECT value FROM transaction_probe")
        }
        #expect(reopenedValue == "preserved")
    }

    @Test("a failed transaction rolls back every write and leaves the connection usable")
    func failedTransactionRollsBackAllWrites() async throws {
        let fixture = try ApplicationLocalTransactionFixture()
        defer { fixture.removeFiles() }
        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Database preparation failed")
            return
        }
        try await datastore.performApplicationLocalWrite { database in
            try database.execute(sql: "CREATE TABLE transaction_probe(value TEXT NOT NULL)")
            try database.execute(sql: "INSERT INTO transaction_probe VALUES ('original')")
        }

        await #expect(throws: ApplicationLocalTransactionFailure.rejected) {
            try await datastore.performApplicationLocalWrite { database in
                try database.execute(sql: "UPDATE transaction_probe SET value = 'changed'")
                try database.execute(sql: "INSERT INTO transaction_probe VALUES ('extra')")
                throw ApplicationLocalTransactionFailure.rejected
            }
        }

        let retainedValues = try await datastore.performApplicationLocalRead { database in
            try String.fetchAll(database, sql: "SELECT value FROM transaction_probe")
        }
        #expect(retainedValues == ["original"])
        try await datastore.performApplicationLocalWrite { database in
            try database.execute(sql: "UPDATE transaction_probe SET value = 'next'")
        }
        let nextValue = try await datastore.performApplicationLocalRead { database in
            try String.fetchOne(database, sql: "SELECT value FROM transaction_probe")
        }
        #expect(nextValue == "next")
    }
}

private enum ApplicationLocalTransactionFailure: Error, Equatable {
    case rejected
}

private struct ApplicationLocalTransactionFixture {
    let rootDirectory: URL
    let localDatabaseURL: URL
    let coreDatabaseURL: URL

    init() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-local-transaction-\(UUIDv7.generate())")
        localDatabaseURL = rootDirectory.appending(path: "local.sqlite")
        coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    func makeDatastore() -> WorkspaceSQLiteDatastoreActor {
        WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        ).makeDatastore()
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
