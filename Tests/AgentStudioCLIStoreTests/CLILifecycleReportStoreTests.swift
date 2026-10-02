import AgentStudioPrimitives
import AgentStudioTestHarness
import Foundation
import GRDB
import Testing

@testable import AgentStudioCLIStore

@Suite("CLI lifecycle report store")
struct CLILifecycleReportStoreTests {
    @Test("the lifecycle migration uses exact TEXT/INTEGER columns, no JSON, triggers or enum CHECK")
    func lifecycleSchemaIsTypedAndImmutable() async throws {
        let observed = try await valueFromDedicatedThread {
            let fixture = try LifecycleStoreFileFixture()
            defer { fixture.remove() }
            return try fixture.writer().databaseQueue.read { database in
                (
                    names: try String.fetchAll(
                        database, sql: "SELECT name FROM pragma_table_info('cli_lifecycle_report')"),
                    types: try String.fetchAll(
                        database, sql: "SELECT type FROM pragma_table_info('cli_lifecycle_report')"),
                    schema: try String.fetchOne(
                        database, sql: "SELECT sql FROM sqlite_master WHERE name='cli_lifecycle_report'"),
                    triggers: try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger'")
                )
            }
        }
        #expect(
            observed.names == [
                "sequence", "report_id", "pane_id", "provider_identifier", "provider_version", "provider_mode",
                "event_name", "conversation_id", "end_reason", "correlation_id", "recorded_at", "boot_session_id",
            ])
        #expect(!observed.types.isEmpty)
        #expect(observed.types.allSatisfy { $0 == "TEXT" || $0 == "INTEGER" })
        let schema = try #require(observed.schema)
        #expect(schema.uppercased().contains("AUTOINCREMENT"))
        #expect(!schema.uppercased().contains("CHECK"))
        #expect(!schema.uppercased().contains("JSON"))
        #expect(observed.triggers == 0)
    }

    @Test("one immutable report round trips and a duplicate id cannot replace its payload")
    func duplicateReportPreservesEnvelope() async throws {
        let observed = try await valueFromDedicatedThread {
            let fixture = try LifecycleStoreFileFixture()
            defer { fixture.remove() }
            let writer = try fixture.writer()
            let original = lifecycleStoreRecord(event: .sessionEnd(reason: "private-display-only"))
            let first = try writer.appendLifecycleReport(original).get()
            let changed = CLILifecycleReportRecord(
                reportID: original.reportID, paneID: original.paneID, providerIdentifier: original.providerIdentifier,
                providerVersion: original.providerVersion, providerMode: original.providerMode, event: .sessionStart,
                conversationID: UUIDv7.generate().uuidString, correlationID: UUIDv7.generate(),
                recordedAt: original.recordedAt.addingTimeInterval(10), bootSessionID: "other-boot")
            let duplicate = try writer.appendLifecycleReport(changed).get()
            return (first, duplicate, try fixture.reader().readLifecycleReports(after: 0).get())
        }
        #expect(observed.0 == observed.1)
        #expect(observed.2.reports == [observed.0])
        #expect(observed.2.issues.isEmpty)
    }

    @Test("field-tagged decode refusal preserves row order without exposing raw reason text")
    func malformedRowCannotHideFollowingReport() async throws {
        let observed = try await valueFromDedicatedThread {
            let fixture = try LifecycleStoreFileFixture()
            defer { fixture.remove() }
            let records = [lifecycleStoreRecord(), lifecycleStoreRecord(event: .sessionEnd(reason: "secret reason"))]
            let seeded = try fixture.seed(records)
            try fixture.writer().databaseQueue.write { database in
                try database.execute(sql: "UPDATE cli_lifecycle_report SET event_name='future-hook' WHERE sequence=1")
            }
            return (seeded, try fixture.reader().readLifecycleReports(after: 0).get())
        }
        #expect(observed.1.reports == [observed.0[1]])
        #expect(observed.1.issues.count == 1)
        #expect(observed.1.issues.first?.sequence == 1)
        #expect(observed.1.issues.first?.field == .eventName)
        #expect(!String(describing: observed.1.issues).contains("secret reason"))
    }

    @Test("a reader cannot append, purge, migrate or change the lifecycle file")
    func appConnectionIsReadOnly() async throws {
        let observed = try await valueFromDedicatedThread {
            let fixture = try LifecycleStoreFileFixture()
            defer { fixture.remove() }
            let record = lifecycleStoreRecord()
            _ = try fixture.seed([record])
            let reader = try fixture.reader()
            return (
                reader.appendLifecycleReport(record),
                reader.purgeHandledLifecycleReports(
                    expectedStoreID: reader.identity.storeID, through: 1, now: fixture.now),
                try reader.databaseQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM cli_lifecycle_report") }
            )
        }
        #expect(observed.0 == .failure(.readOnly))
        #expect(observed.1 == .failure(.readOnly))
        #expect(observed.2 == 1)
    }

    @Test("purge requires both handled mark and age; unread ends never expire and ids are never reused")
    func cleanupCannotEraseUnreadEnd() async throws {
        let observed = try await valueFromDedicatedThread {
            let fixture = try LifecycleStoreFileFixture()
            defer { fixture.remove() }
            let old = fixture.now.addingTimeInterval(-86_401)
            let seeded = try fixture.seed([
                lifecycleStoreRecord(at: old), lifecycleStoreRecord(at: fixture.now),
                lifecycleStoreRecord(event: .sessionEnd(reason: "exit"), at: old),
            ])
            let writer = try fixture.writer()
            let removed = try writer.purgeHandledLifecycleReports(
                expectedStoreID: writer.identity.storeID, through: 2, now: fixture.now
            ).get()
            let remaining = try writer.readLifecycleReports(after: 0).get()
            let next = try writer.appendLifecycleReport(lifecycleStoreRecord()).get()
            return (seeded, removed, remaining, next)
        }
        #expect(observed.1 == 1)
        #expect(observed.2.reports == Array(observed.0.dropFirst()))
        #expect(observed.3.sequence > observed.0[2].sequence)
    }
}
