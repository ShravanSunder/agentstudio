import AgentStudioIPCClientCore
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioSessions
import AgentStudioTestHarness
import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudio
@testable import AgentStudioCLIStore
@testable import AgentStudioCore

@MainActor
@Suite(
    "CLI lifecycle readiness and read-through", .serialized,
    SessionsVerticalHarnessTrait(providerProfiles: .claudeCodeAndCodex))
struct CLILifecycleReadinessTests {
    @Test("the authenticated session.event route dispositions its real store receipt in the prepared App datastore")
    func liveIPCReceiptReachesPreparedCursor() async throws {
        let harness = try await #require(SessionsVerticalHarnessContext.current).freshPanePair()
        let paneID = harness.boundPaneId
        let storeURL = harness.appDelegate.appIPCPaths.cliStoreURL
        let sessionID = UUIDv7.generate().uuidString
        let reportID = UUIDv7.generate()
        let correlationID = UUIDv7.generate()
        let storeID = try await valueFromDedicatedThread {
            let writer = try CLIStore.openWriter(url: storeURL, channel: .debug).get()
            try writer.databaseQueue.write { database in
                // Test-owned schema while RED; GREEN must use the real migration.
                try database.execute(sql: intakeTestLifecycleSchema)
                try database.execute(
                    sql: """
                        INSERT INTO cli_lifecycle_report
                        (report_id,pane_id,provider_identifier,provider_version,provider_mode,event_name,
                         conversation_id,end_reason,correlation_id,recorded_at,boot_session_id)
                        VALUES (?,?,'codex','0.154.0','cli','sessionStart',?,NULL,?,1700000000000,'test-boot')
                        """, arguments: [reportID.uuidString, paneID.uuidString, sessionID, correlationID.uuidString])
            }
            return writer.identity.storeID
        }
        let provider = IPCSessionProviderIdentity(identifier: "codex", version: "0.154.0", mode: "cli")
        let event = IPCSessionEventIdentity(
            name: .sessionStart, conversationId: sessionID, turnId: nil, requestId: nil, toolId: nil,
            subagentId: nil, occurrenceId: reportID)
        let params = IPCSessionEventParams(
            handle: paneID.uuidString, provider: provider, event: event, correlationId: correlationID,
            lifecycleReport: .init(storeId: storeID, sequence: 1))
        #expect(try await harness.sessionEvent(params: params).disposition == .admitted)
        let snapshot = try await harness.paneSnapshot(paneId: paneID)
        #expect(snapshot.currentBinding?.providerConversationId == sessionID)
        let prepared = harness.appDelegate.workspaceSQLiteDatastore
        let datastore = try #require(prepared)
        let mark = try await datastore.performApplicationLocalRead {
            try Int64.fetchOne(
                $0, sql: "SELECT last_handled_sequence FROM sessions_cli_report_cursor WHERE store_id=?",
                arguments: [storeID.uuidString])
        }
        #expect(mark == 1)
    }

    @Test("newer or corrupt CLI files make readiness unavailable", arguments: [false, true])
    func invalidStoreNeverPublishesReady(corrupt: Bool) async throws {
        try await withLifecycleIntakeFixture { fixture in
            let readerFailure = try await valueFromDedicatedThread { () -> CLIStoreFailure? in
                if corrupt {
                    try Data("not a SQLite database".utf8).write(to: fixture.storeURL)
                } else {
                    let writer = try CLIStore.openWriter(url: fixture.storeURL, channel: .debug).get()
                    try writer.databaseQueue.write {
                        try $0.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES ('999_future_schema')")
                    }
                }
                switch CLIStore.openReader(url: fixture.storeURL, expectedChannel: .debug) {
                case .success: return nil
                case .failure(let reason): return reason
                }
            }
            #expect(readerFailure == (corrupt ? .unavailable : .superseded))
            let readiness = makeLifecycleReadiness()
            await AppIPCDeferredInitialization.prepareResumeReadiness(
                readiness: readiness, intake: fixture.intake(), prepareForLaunch: {})
            #expect(await readiness.wait(paneId: fixture.paneID) == .unavailable)
            await readiness.shutdown()
        }
    }

    @Test("S0 intake after the sweep replaces old A with pending B before the cold verdict is decided")
    func pendingHistoricalBindingOwnsReadinessVerdict() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let old = fixture.record()
            _ = try await fixture.adapter().recordProviderEvent(
                paneId: fixture.paneID, params: fixture.params(old), provenance: .matchingPane)
            let pending = try await fixture.seed(fixture.record())
            let readiness = makeLifecycleReadiness()
            do {
                await AppIPCDeferredInitialization.prepareResumeReadiness(
                    readiness: readiness, intake: fixture.intake(),
                    prepareForLaunch: { _ = try await fixture.ingestion.prepareForLaunch(at: fixture.now) })
                #expect(await readiness.wait(paneId: fixture.paneID) == .ready)
                let fetched = try await fixture.binding()
                #expect(fetched?.providerConversationId == pending.record.conversationID)
                #expect(fetched?.providerConversationId != old.conversationID)
                #expect(fetched?.startedFromHistoricalReport == true)
                #expect(try await fixture.state().mark == pending.sequence)
                #expect(try await fixture.sameProviderLookVerdict() == .unknown(.startedFromHistoricalReport))
                await readiness.shutdown()
            } catch {
                await readiness.shutdown()
                throw error
            }
        }
    }

    @Test("the real prepared Core writer owns the Sessions effect and lifecycle cursor, and login returns that mark")
    func realDatastoreTransactionAndReadThrough() async throws {
        try await withLifecycleIntakeFixture { fixture in
            await fixture.close()
            let datastore = try await prepareLifecycleDatastore(fixture: fixture)
            let access = WorkspaceSessionsSQLiteAccess(datastore: datastore)
            let ingestion = SessionsIngestion(
                repository: SessionsRepository(sqliteAccess: access),
                limits: .init(maximumPendingPerPane: 16, maximumPendingGlobal: 32), probe: { _ in })
            do {
                let adapter = AgentStudioIPCSessionsAdapter(
                    ingestion: ingestion, providerRegistry: .init(profiles: [.codexCommandLine]), now: { fixture.now })
                let intake = CLILifecycleReportIntake(
                    storeURL: fixture.storeURL, expectedChannel: .debug, admission: adapter, sqliteAccess: access,
                    paneExists: { $0 == fixture.paneID })
                let row = try await fixture.seed(fixture.record())
                let boundary = try await intake.captureListenerReadyBoundary()
                try await intake.takeIn(through: boundary)
                let snapshot = try await ingestion.snapshot(.pane(fixture.paneID, page: .init(limit: 10, after: nil)))
                #expect(snapshot.currentBinding?.providerConversationId == row.record.conversationID)
                let mark = try await datastore.performApplicationLocalRead { database in
                    try Int64.fetchOne(
                        database, sql: "SELECT last_handled_sequence FROM sessions_cli_report_cursor WHERE store_id=?",
                        arguments: [fixture.storeID.uuidString])
                }
                #expect(mark == row.sequence)
                // The independent outbox cursor is zero, not replaced by the lifecycle mark.
                try await datastore.performApplicationLocalWrite { database in
                    try database.execute(
                        sql: "INSERT INTO pane_context_cli_outbox_cursor VALUES (?,0)",
                        arguments: [fixture.storeID.uuidString])
                }
                let through = await AppCLIStoreReadThroughReader(
                    storeURL: fixture.storeURL, expectedChannel: .debug, datastore: datastore
                ).readThrough()
                #expect(through?.storeId == fixture.storeID)
                #expect(through?.outbox == 0)
                #expect(through?.lifecycleReport == row.sequence)
                await ingestion.finish()
            } catch {
                await ingestion.finish()
                throw error
            }
        }
    }

    @Test(
        "controlled expiry cleans only login's acknowledged prefix, preserving unread ends and their known-exited verdict"
    )
    func loginCleanupCannotExpireUnreadEnd() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            let start = try await fixture.seed(fixture.record())
            _ = try await intake.recordLive(
                paneId: fixture.paneID, params: fixture.params(start.record, sequence: start.sequence))
            let end = try await fixture.seed(
                fixture.record(sessionID: start.record.conversationID, event: .sessionEnd(reason: "exit")))
            let clock = TestPushClock()
            let origin = clock.now
            clock.advance(by: .seconds(86_401))
            let elapsed = origin.duration(to: clock.now).components.seconds
            let cleanup = CLIStoreCleanupHandler(
                environment: [
                    "AGENTSTUDIO_CLI_STORE": fixture.storeURL.path, "AGENTSTUDIO_CLI_STORE_CHANNEL": "debug",
                ],
                now: { fixture.now.addingTimeInterval(Double(elapsed)) }, diagnosticSink: { _ in })
            await valueFromDedicatedThread {
                cleanup.handle(readThrough: .init(storeId: fixture.storeID, outbox: 0, lifecycleReport: start.sequence))
            }
            let remaining = try await valueFromDedicatedThread {
                try CLIStore.openReader(url: fixture.storeURL, expectedChannel: .debug).get().readLifecycleReports(
                    after: 0
                ).get().reports
            }
            #expect(remaining.map { $0.sequence } == [end.sequence])
            try await intake.takeIn(through: .stored(storeId: fixture.storeID, sequence: end.sequence))
            #expect(try await fixture.sameProviderLookVerdict() == .knownExited(.personExit))
        }
    }

    @Test(
        "production local migrations create the cursor between 017 and 019 without reshaping an existing 019 database")
    func cursorMigrationUpgradesAlreadyAppliedOutbox() async throws {
        let observed = try await valueFromDedicatedThread {
            let database = try DatabaseQueue()
            let previous = WorkspaceLocalMigrations.migrator
            // A previous release's migration history can include 019 without 018.
            try previous.migrate(database)
            try database.write { database in
                try database.execute(
                    sql: "DELETE FROM grdb_migrations WHERE identifier='018_create_sessions_cli_report_cursor'")
                if try database.tableExists("sessions_cli_report_cursor") {
                    try database.execute(sql: "DROP TABLE sessions_cli_report_cursor")
                }
                try database.execute(sql: "INSERT INTO pane_context_cli_outbox_cursor VALUES ('preserved-store',7)")
            }
            try WorkspaceLocalMigrations.migrate(database)
            return try database.read { database in
                (
                    exists: try database.tableExists("sessions_cli_report_cursor"),
                    preserved: try Int64.fetchOne(
                        database,
                        sql:
                            "SELECT last_handled_id FROM pane_context_cli_outbox_cursor WHERE store_id='preserved-store'"
                    ),
                    migrations: try WorkspaceLocalMigrations.migrator.completedMigrations(database)
                )
            }
        }
        #expect(observed.exists)
        #expect(observed.preserved == 7)
        let cursorIndex = try #require(observed.migrations.firstIndex(of: "018_create_sessions_cli_report_cursor"))
        let foregroundIndex = try #require(
            observed.migrations.firstIndex(of: "017_create_terminal_pane_foreground_observation"))
        let outboxIndex = try #require(observed.migrations.firstIndex(of: "019_create_pane_context_cli_outbox_cursor"))
        #expect(foregroundIndex < cursorIndex && cursorIndex < outboxIndex)
    }
}

private func makeLifecycleReadiness() -> RestoreResumeReadiness<TestPushClock> {
    .init(clock: TestPushClock(), deadline: .seconds(2), launchId: UUIDv7.generate(), factSink: { _, _ in })
}

private func prepareLifecycleDatastore(fixture: LifecycleIntakeFileFixture) async throws
    -> WorkspaceSQLiteDatastoreActor
{
    let prepared = try await valueFromDedicatedThread {
        let coreQueue = try DatabaseQueue(path: fixture.rootURL.appending(path: "core.sqlite").path)
        let core = WorkspaceCoreRepository(databaseWriter: coreQueue)
        try core.migrate()
        let local = WorkspaceLocalRepository(workspaceId: UUIDv7.generate(), databaseWriter: fixture.access.queue)
        return (core, local)
    }
    return try await preparedWorkspaceSQLiteDatastore(
        coreRepository: prepared.0, preparedApplicationLocalRepository: prepared.1)
}
