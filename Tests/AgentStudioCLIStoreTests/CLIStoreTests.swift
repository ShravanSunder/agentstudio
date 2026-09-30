import AgentStudioPrimitives
import AgentStudioTestHarness
import AgentStudioTestSupport
import Foundation
import GRDB
import Synchronization
import Testing

@testable import AgentStudioCLIStore

@Suite("CLI store")
struct CLIStoreTests {
    @Test("writer migrates an empty file and reopens the same UUIDv7 identity")
    func writerCreatesAndPreservesIdentity() async throws {
        try await valueFromDedicatedThread {
            // Arrange
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }

            // Act
            let first = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()
            let second = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()

            // Assert
            #expect(UUIDv7.isV7(first.identity.storeID))
            #expect(first.identity == second.identity)
            #expect(first.identity.channel == .debug)
            try first.databaseQueue.read { database throws in
                #expect(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM cli_store_identity") == 1)
                #expect(try database.tableExists("cli_outbox"))
                #expect(
                    try CLIStoreMigrator.makeMigrator(channel: .debug).appliedMigrations(database)
                        == [CLIStoreMigrator.identityMigration, CLIStoreMigrator.outboxMigration])
            }
        }
    }

    @Test("the schema uses only TEXT and INTEGER with no enum CHECK, triggers or foreign keys")
    func schemaPreservesAdditiveEvolution() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let store = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()

            try store.databaseQueue.read { database throws in
                for table in ["cli_store_identity", "cli_outbox"] {
                    let types = try String.fetchAll(
                        database, sql: "SELECT type FROM pragma_table_info(?)", arguments: [table])
                    #expect(!types.isEmpty)
                    #expect(types.allSatisfy { $0 == "TEXT" || $0 == "INTEGER" })
                    let storedSchema = try String.fetchOne(
                        database, sql: "SELECT sql FROM sqlite_master WHERE name = ?", arguments: [table])
                    let schema = try #require(storedSchema)
                    #expect(!schema.uppercased().contains("CHECK"))
                    #expect(!schema.uppercased().contains("REFERENCES"))
                }
                #expect(
                    try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger'") == 0)
            }
        }
    }

    @Test("file connections use WAL and a 50 ms SQLite busy timeout")
    func connectionsUseWALAndShortBusyTimeout() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let writer = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()
            let reader = try CLIStore.openReader(url: fixture.databaseURL, expectedChannel: .debug).get()

            for store in [writer, reader] {
                try store.databaseQueue.read { database throws in
                    #expect(try String.fetchOne(database, sql: "PRAGMA journal_mode") == "wal")
                    #expect(try Int.fetchOne(database, sql: "PRAGMA busy_timeout") == 50)
                }
            }
        }
    }

    @Test("a previous-version reader does not migrate; the next writer upgrades without replacing identity")
    func previousVersionIsReadOnlyUntilWriterMigrates() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let previous = try DatabaseQueue(path: fixture.databaseURL.path)
            let migrator = CLIStoreMigrator.makeMigrator(channel: .beta)
            try migrator.migrate(previous, upTo: CLIStoreMigrator.identityMigration)
            let storedIdentity = try previous.read { database in
                try String.fetchOne(database, sql: "SELECT store_id FROM cli_store_identity")
            }
            let originalIdentity = try #require(storedIdentity)

            let reader = try CLIStore.openReader(url: fixture.databaseURL, expectedChannel: .beta).get()
            #expect(try reader.readOutbox(after: 0).get().entries.isEmpty)
            try previous.read { database throws in
                #expect(try migrator.appliedMigrations(database) == [CLIStoreMigrator.identityMigration])
                #expect(try !database.tableExists("cli_outbox"))
            }

            let writer = try CLIStore.openWriter(url: fixture.databaseURL, channel: .beta).get()
            #expect(writer.identity.storeID.uuidString == originalIdentity)
            #expect(writer.identity.channel == .beta)
            #expect(try writer.databaseQueue.read { try $0.tableExists("cli_outbox") })
        }
    }

    @Test("an append round trips a typed immutable notice; the wire payload stays opaque")
    func noticeRoundTripsWithoutInterpretingPayload() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let writer = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()
            let paneID = UUIDv7.generate()
            let messageID = UUIDv7.generate()
            let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            let inserted = try writer.appendNotice(
                paneID: paneID, messageID: messageID,
                payloadJSON: "opaque to the store; decoded only by live admission", createdAt: createdAt
            ).get()
            let reader = try CLIStore.openReader(url: fixture.databaseURL, expectedChannel: .debug).get()

            let batch = try reader.readOutbox(after: 0).get()
            #expect(batch.entries == [inserted])
            #expect(batch.lastReadID == inserted.id)
            guard case .notice(let notice) = inserted else { return }
            #expect(notice.paneID == paneID)
            #expect(notice.messageID == messageID)
            #expect(notice.createdAt == createdAt)
            #expect(notice.payloadJSON == "opaque to the store; decoded only by live admission")
            #expect(try reader.readOutbox(after: inserted.id).get().entries.isEmpty)
        }
    }

    @Test("duplicate message ids preserve the first notice without mutating it")
    func duplicateAppendPreservesOriginalNotice() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let writer = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()
            let paneID = UUIDv7.generate()
            let messageID = UUIDv7.generate()
            let original = try writer.appendNotice(
                paneID: paneID, messageID: messageID, payloadJSON: "original", createdAt: fixture.createdAt
            ).get()

            let duplicate = try writer.appendNotice(
                paneID: paneID, messageID: messageID, payloadJSON: "must not replace original",
                createdAt: fixture.createdAt.addingTimeInterval(10)
            ).get()

            #expect(duplicate == original)
            #expect(try writer.readOutbox(after: 0).get().entries == [original])
        }
    }

    @Test("outbox ids keep increasing after every prior row has been purged")
    func deletedPrefixDoesNotReuseIDs() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let writer = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()
            let first = try fixture.append(to: writer)
            try writer.databaseQueue.write { database in
                try database.execute(sql: "DELETE FROM cli_outbox")
            }

            let second = try fixture.append(to: writer)

            #expect(second.id > first.id)
            #expect(try writer.readOutbox(after: first.id).get().entries == [second])
        }
    }

    @Test("an actual write through the app reader fails at the SQLite boundary")
    func readerCannotWrite() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let writer = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()
            let original = try fixture.append(to: writer)
            let reader = try CLIStore.openReader(url: fixture.databaseURL, expectedChannel: .debug).get()

            #expect(throws: (any Error).self) {
                try reader.databaseQueue.writeWithoutTransaction { database in
                    try database.execute(sql: "DELETE FROM cli_outbox")
                }
            }
            #expect(
                failure(
                    in: reader.appendNotice(
                        paneID: UUIDv7.generate(), messageID: UUIDv7.generate(),
                        payloadJSON: "reader write", createdAt: fixture.createdAt)) == .readOnly)
            #expect(try writer.readOutbox(after: 0).get().entries == [original])
        }
    }

    @Test("a reader never creates a missing store or its parent")
    func missingReaderFailsOpenWithoutCreatingFiles() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let missingURL = fixture.rootURL.appending(path: "absent/cli.sqlite")

            #expect(failure(in: CLIStore.openReader(url: missingURL, expectedChannel: .debug)) == .unavailable)
            #expect(!FileManager.default.fileExists(atPath: missingURL.deletingLastPathComponent().path))
        }
    }

    @Test("corruption is fail-open and the original bytes are preserved")
    func corruptStoreFailsOpenWithoutReplacement() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let corrupt = Data("not a SQLite database".utf8)
            try corrupt.write(to: fixture.databaseURL)

            #expect(failure(in: CLIStore.openWriter(url: fixture.databaseURL, channel: .debug)) == .unavailable)
            #expect(failure(in: CLIStore.openReader(url: fixture.databaseURL, expectedChannel: .debug)) == .unavailable)
            #expect(try Data(contentsOf: fixture.databaseURL) == corrupt)
        }
    }

    @Test("a store from a newer migrator disables writes and preserves its rows")
    func supersededWriterDoesNotTouchRows() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let writer = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()
            let original = try fixture.append(to: writer)
            var futureMigrator = CLIStoreMigrator.makeMigrator(channel: .debug)
            futureMigrator.registerMigration("003_future_cli_schema") { database in
                try database.execute(sql: "CREATE TABLE future_cli_table (value TEXT)")
            }
            try futureMigrator.migrate(writer.databaseQueue)

            #expect(failure(in: CLIStore.openWriter(url: fixture.databaseURL, channel: .debug)) == .superseded)
            #expect(try writer.readOutbox(after: 0).get().entries == [original])
            #expect(try writer.databaseQueue.read { try $0.tableExists("future_cli_table") })
        }
    }

    @Test("a held writer lock produces a typed busy outcome without a queued row")
    func heldWriteLockFailsOpen() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let holder = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()
            let writer = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()
            try holder.databaseQueue.writeWithoutTransaction { database in
                try database.execute(sql: "BEGIN IMMEDIATE")
            }
            defer {
                try? holder.databaseQueue.writeWithoutTransaction { database in
                    try database.execute(sql: "ROLLBACK")
                }
            }

            let outcome = writer.appendNotice(
                paneID: UUIDv7.generate(), messageID: UUIDv7.generate(),
                payloadJSON: "locked", createdAt: fixture.createdAt)

            #expect(failure(in: outcome) == .busy)
            #expect(try holder.readOutbox(after: 0).get().entries.isEmpty)
        }
    }

    @Test("writer and reader refuse a foreign channel without changing identity")
    func mismatchedChannelIsRefused() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let original = try CLIStore.openWriter(url: fixture.databaseURL, channel: .beta).get()

            #expect(failure(in: CLIStore.openWriter(url: fixture.databaseURL, channel: .stable)) == .channelMismatch)
            #expect(
                failure(in: CLIStore.openReader(url: fixture.databaseURL, expectedChannel: .debug)) == .channelMismatch)
            #expect(
                try CLIStore.openReader(url: fixture.databaseURL, expectedChannel: .beta).get().identity
                    == original.identity)
        }
    }

    @Test("unknown identity channels fail closed instead of defaulting to stable")
    func unknownIdentityChannelIsRefused() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let original = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()
            try original.databaseQueue.write { database in
                try database.execute(sql: "UPDATE cli_store_identity SET channel = 'future-channel'")
            }

            #expect(failure(in: CLIStore.openWriter(url: fixture.databaseURL, channel: .debug)) == .invalidIdentity)
            #expect(
                failure(in: CLIStore.openReader(url: fixture.databaseURL, expectedChannel: .debug)) == .invalidIdentity)
        }
    }

    @Test("unknown outbox kinds are skipped and logged with the field, while later notices survive")
    func unknownKindIsSkippedAndLogged() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let writer = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()
            let first = try fixture.append(to: writer)
            try writer.databaseQueue.write { database in
                try database.execute(
                    sql: "UPDATE cli_outbox SET kind = 'future-kind' WHERE id = ?", arguments: [first.id])
            }
            let second = try fixture.append(to: writer)
            let issues = Mutex<[CLIStoreDecodeIssue]>([])
            let reader = try CLIStore.openReader(
                url: fixture.databaseURL, expectedChannel: .debug,
                logDecodeIssue: { issue in issues.withLock { $0.append(issue) } }
            ).get()

            let batch = try reader.readOutbox(after: 0).get()

            #expect(batch.entries == [second])
            #expect(batch.lastReadID == second.id)
            #expect(issues.withLock { $0 } == [.init(rowID: first.id, field: .kind)])
            #expect(try writer.databaseQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM cli_outbox") } == 2)
        }
    }

    @Test("a skipped final row remains part of the read prefix")
    func skippedFinalRowStillReportsReadPosition() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreFileFixture()
            defer { fixture.remove() }
            let writer = try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()
            let last = try fixture.append(to: writer)
            try writer.databaseQueue.write { database in
                try database.execute(sql: "UPDATE cli_outbox SET kind = 'future-kind'")
            }

            let batch = try writer.readOutbox(after: 0).get()

            #expect(batch.entries.isEmpty)
            #expect(batch.lastReadID == last.id)
            #expect(try writer.readOutbox(after: last.id).get().lastReadID == last.id)
        }
    }

    @Test("two real CLI writer processes preserve every successful append and monotonic ids")
    func multipleProcessesAppendToOneFile() async throws {
        let fixture = try CLIStoreFileFixture()
        defer { fixture.remove() }
        _ = try await valueFromDedicatedThread {
            try CLIStore.openWriter(url: fixture.databaseURL, channel: .debug).get()
        }
        let executableURL = try fixture.processExecutableURL()

        async let first = runProcessToExit(
            executableURL: executableURL, arguments: [fixture.databaseURL.path, UUIDv7.generate().uuidString])
        async let second = runProcessToExit(
            executableURL: executableURL, arguments: [fixture.databaseURL.path, UUIDv7.generate().uuidString])
        let outputs = try await [first, second]

        var reportedIDs: [Int64] = []
        for output in outputs {
            let standardError = String(bytes: output.standardError, encoding: .utf8) ?? "<non-UTF8 stderr>"
            #expect(output.terminationStatus == 0, "stderr: \(standardError)")
            let standardOutput = try #require(String(bytes: output.standardOutput, encoding: .utf8))
            let lines = standardOutput.split(separator: "\n")
            #expect(lines.count == 16)
            #expect(lines.allSatisfy { $0 == "busy" || Int64($0) != nil })
            let successfulIDs = lines.compactMap { Int64($0) }
            #expect(successfulIDs == successfulIDs.sorted())
            reportedIDs.append(contentsOf: successfulIDs)
        }
        #expect(!reportedIDs.isEmpty)
        #expect(Set(reportedIDs).count == reportedIDs.count)
        let expectedIDs = reportedIDs.sorted()
        #expect(expectedIDs == Array(Int64(1)...Int64(max(1, expectedIDs.count))))
        try await valueFromDedicatedThread {
            let reader = try CLIStore.openReader(url: fixture.databaseURL, expectedChannel: .debug).get()
            #expect(try reader.readOutbox(after: 0).get().entries.map(\.id) == expectedIDs)
        }
    }
}

private func failure<Value>(in result: Result<Value, CLIStoreFailure>) -> CLIStoreFailure? {
    switch result {
    case .success: nil
    case .failure(let failure): failure
    }
}

private struct CLIStoreFileFixture: Sendable {
    let rootURL: URL
    let databaseURL: URL
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appending(path: "cli-store-\(UUIDv7.generate().uuidString)")
        databaseURL = rootURL.appending(path: "cli.sqlite")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func append(to writer: CLIStore) throws -> CLIOutboxEntry {
        try writer.appendNotice(
            paneID: UUIDv7.generate(), messageID: UUIDv7.generate(),
            payloadJSON: #"{"jsonrpc":"2.0","method":"session.message"}"#, createdAt: createdAt
        ).get()
    }

    func processExecutableURL() throws -> URL {
        let buildDirectory = try #require(ProcessInfo.processInfo.environment["SWIFT_BUILD_DIR"])
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let buildURL =
            buildDirectory.hasPrefix("/")
            ? URL(fileURLWithPath: buildDirectory) : projectRoot.appending(path: buildDirectory)
        return buildURL.appending(path: "debug/agentstudio-cli-store-process-fixture")
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
