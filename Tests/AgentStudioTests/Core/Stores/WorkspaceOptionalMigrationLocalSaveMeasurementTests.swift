import AgentStudioInfrastructure
import CoreGraphics
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

enum OptionalMigrationSchemaState: String, CaseIterable, Sendable {
    case fresh
    case steady
}

@Suite("Optional migration and local save measurement", .serialized)
struct OptionalMigrationLocalSaveMeasurementTests {
    @Test(
        "real optional migration and local save expose bounded contention measurements",
        arguments: OptionalMigrationSchemaState.allCases
    )
    func optionalMigrationAndLocalSaveMeasurement(
        schemaState: OptionalMigrationSchemaState
    ) async throws {
        let sampleCount = 10
        var reports: [OptionalMigrationLocalSaveSampleReport] = []

        for sampleIndex in 0..<sampleCount {
            let report = try await runMeasurementSample(
                schemaState: schemaState,
                sampleIndex: sampleIndex
            )
            reports.append(report)
        }

        #expect(reports.count == sampleCount)
        #expect(reports.allSatisfy { $0.writerIdentityCount == 1 })
        #expect(reports.allSatisfy { $0.migrationStatementCount > 0 })
        #expect(reports.allSatisfy { $0.localSaveStatementCount > 0 })
        printMeasurementReport(schemaState: schemaState, samples: reports)
    }
}

private func runMeasurementSample(
    schemaState: OptionalMigrationSchemaState,
    sampleIndex: Int
) async throws -> OptionalMigrationLocalSaveSampleReport {
    let fixture = try OptionalMigrationLocalSaveFixture(schemaState: schemaState)
    defer { fixture.closeAndRemoveFiles() }
    let clock = ContinuousClock()
    let saveCallTiming = LocalSaveSynchronousCallTiming(clock: clock)
    let saveTask = Task {
        guard await fixture.traceRecorder.waitForMigrationTrigger() else {
            throw OptionalMigrationMeasurementError.missingMigrationTrigger
        }
        let submissionInstant = clock.now
        try await fixture.datastore.performLocalSaveOperation(workspaceId: fixture.workspaceID) { repository in
            try saveCallTiming.measure {
                try repository.replaceWorkspaceSnapshotLocalState(
                    cursorState: fixture.cursorState,
                    windowState: fixture.windowState,
                    completedAt: fixture.completedAt
                )
            }
        }
        return LocalSaveTaskTiming(
            submissionInstant: submissionInstant,
            actorCallCompletionInstant: clock.now,
            synchronousCallInterval: try saveCallTiming.requiredInterval()
        )
    }

    let migrationCallStart = clock.now
    let migrationResult = await fixture.datastore.prepareOptionalApplicationLocalSchema()
    let migrationCallEnd = clock.now
    fixture.traceRecorder.finishMigrationTriggerWait()
    let saveTimingResult: Result<LocalSaveTaskTiming, Error>
    do {
        saveTimingResult = .success(try await saveTask.value)
    } catch {
        saveTimingResult = .failure(error)
    }
    guard case .ready = migrationResult else {
        throw OptionalMigrationMeasurementError.optionalMigrationUnavailable
    }
    let saveTiming = try saveTimingResult.get()

    let traceSnapshot = fixture.traceRecorder.snapshot()
    let migrationTrace = try traceSnapshot.requireMigrationTrace()
    let localSaveTrace = try traceSnapshot.requireLocalSaveTrace()
    let completedMigrationIdentifiers = try await fixture.localDatabasePool.read { database in
        try WorkspaceLocalMigrations.migrator.completedMigrations(database)
    }

    #expect(completedMigrationIdentifiers == expectedLocalMigrationIdentifiers)
    #expect(try fixture.localRepository.fetchCursorState() == fixture.cursorState)
    #expect(try fixture.localRepository.fetchWindowState() == fixture.windowState)
    #expect(traceSnapshot.writerIdentityCount == 1)

    let overlapObserved =
        saveTiming.submissionInstant >= migrationTrace.firstStatementInstant
        && saveTiming.submissionInstant <= migrationTrace.lastProfileInstant
    return OptionalMigrationLocalSaveSampleReport(
        sampleIndex: sampleIndex,
        overlapCategory: overlapObserved ? "traced_sql_overlap" : "non_overlap",
        migrationCallUpperBoundMilliseconds: milliseconds(
            from: migrationCallStart.duration(to: migrationCallEnd)
        ),
        migrationSQLComponentMilliseconds: migrationTrace.profileDurationMilliseconds,
        migrationSQLEnvelopeMilliseconds: milliseconds(
            from: migrationTrace.firstStatementInstant.duration(to: migrationTrace.lastProfileInstant)
        ),
        saveSubmissionToFirstSQLAdmissionUpperBoundMilliseconds: milliseconds(
            from: saveTiming.submissionInstant.duration(to: localSaveTrace.firstStatementInstant)
        ),
        localRepositorySynchronousCallMilliseconds: milliseconds(
            from: saveTiming.synchronousCallInterval.start.duration(
                to: saveTiming.synchronousCallInterval.end
            )
        ),
        localSaveActorCallMilliseconds: milliseconds(
            from: saveTiming.submissionInstant.duration(to: saveTiming.actorCallCompletionInstant)
        ),
        migrationStatementCount: migrationTrace.statementCount,
        localSaveStatementCount: localSaveTrace.statementCount,
        writerIdentityCount: traceSnapshot.writerIdentityCount
    )
}

private struct OptionalMigrationLocalSaveFixture {
    let rootDirectory: URL
    let localDatabasePool: DatabasePool
    let localRepository: WorkspaceLocalRepository
    let datastore: WorkspaceSQLiteDatastoreActor
    let traceRecorder: OptionalMigrationLocalSaveTraceRecorder
    let workspaceID: UUID
    let cursorState: WorkspaceLocalRepository.CursorStateRecord
    let windowState: WorkspaceLocalRepository.WindowStateRecord
    let completedAt: Date

    init(schemaState: OptionalMigrationSchemaState) throws {
        rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "agentstudio-optional-migration-measurement-\(UUIDv7.generate())"
        )
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        traceRecorder = OptionalMigrationLocalSaveTraceRecorder(schemaState: schemaState)
        var localConfiguration = SQLiteDatabaseFactory.makeConfiguration(
            label: "AgentStudio.sqlite.optional-migration-measurement.local"
        )
        localConfiguration.journalMode = .wal
        localConfiguration.publicStatementArguments = false
        let recorder = traceRecorder
        localConfiguration.prepareDatabase { database in
            guard !database.configuration.readonly else { return }
            let writerIdentity = ObjectIdentifier(database)
            recorder.registerWriterIdentity(writerIdentity)
            database.trace(options: [.statement, .profile]) { event in
                recorder.record(event, writerIdentity: writerIdentity)
            }
        }
        localDatabasePool = try DatabasePool(
            path: rootDirectory.appending(path: "local.sqlite").path,
            configuration: localConfiguration
        )
        switch schemaState {
        case .fresh:
            try WorkspaceLocalMigrations.migrateBootRequired(localDatabasePool)
        case .steady:
            try WorkspaceLocalMigrations.migrate(localDatabasePool)
        }

        let applicationRepository = WorkspaceLocalRepository(
            workspaceId: UUIDv7.generate(),
            databaseWriter: localDatabasePool
        )
        let coreDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.optional-migration-measurement.core"
        )
        try WorkspaceCoreMigrations.migrate(coreDatabaseQueue)
        datastore = WorkspaceSQLiteDatastoreActor(
            preparedCoreRepository: WorkspaceCoreRepository(databaseWriter: coreDatabaseQueue),
            preparationReceipt: .init(core: .uninitialized, local: .available(recovery: nil)),
            preparedApplicationLocalRepository: applicationRepository
        )

        workspaceID = UUIDv7.generate()
        localRepository = WorkspaceLocalRepository(
            workspaceId: workspaceID,
            databaseWriter: localDatabasePool
        )
        let tabID = UUIDv7.generate()
        let arrangementID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let drawerID = UUIDv7.generate()
        cursorState = .init(
            activeTabId: tabID,
            activeArrangementIdsByTabId: [tabID: arrangementID],
            activePaneIdsByArrangementId: [arrangementID: paneID],
            drawerExpansionByDrawerId: [drawerID: true],
            activeChildIdsByArrangementDrawer: [
                .init(arrangementId: arrangementID, drawerId: drawerID): paneID
            ]
        )
        windowState = .init(
            sidebarWidth: 321,
            windowFrame: CGRect(x: 11, y: 22, width: 1234, height: 789)
        )
        completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        traceRecorder.beginMeasurement()
    }

    func closeAndRemoveFiles() {
        try? localDatabasePool.close()
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}

private final class OptionalMigrationLocalSaveTraceRecorder: @unchecked Sendable {
    private let clock = ContinuousClock()
    private let lock = NSLock()
    private let migrationTrigger = AsyncStream<Void>.makeStream()
    private let schemaState: OptionalMigrationSchemaState
    private var isMeasurementActive = false
    private var didSignalMigrationTrigger = false
    private var writerIdentities: Set<ObjectIdentifier> = []
    private var events: [OptionalMigrationLocalSaveTraceEvent] = []

    init(schemaState: OptionalMigrationSchemaState) {
        self.schemaState = schemaState
    }

    func registerWriterIdentity(_ writerIdentity: ObjectIdentifier) {
        _ = lock.withLock {
            writerIdentities.insert(writerIdentity)
        }
    }

    func beginMeasurement() {
        lock.withLock {
            events.removeAll(keepingCapacity: true)
            isMeasurementActive = true
        }
    }

    func record(_ event: Database.TraceEvent, writerIdentity: ObjectIdentifier) {
        let instant = clock.now
        let recordedEvent: OptionalMigrationLocalSaveTraceEvent
        switch event {
        case .statement(let statement):
            recordedEvent = .statement(
                instant: instant,
                writerIdentity: writerIdentity,
                sql: statement.sql
            )
        case .profile(let statement, let duration):
            recordedEvent = .profile(
                instant: instant,
                writerIdentity: writerIdentity,
                sql: statement.sql,
                durationMilliseconds: duration * 1000
            )
        @unknown default:
            return
        }

        var shouldSignal = false
        lock.withLock {
            guard isMeasurementActive else { return }
            events.append(recordedEvent)
            if !didSignalMigrationTrigger,
                case .statement(_, _, let sql) = recordedEvent,
                isMigrationTriggerStatement(sql)
            {
                didSignalMigrationTrigger = true
                shouldSignal = true
            }
        }
        if shouldSignal {
            migrationTrigger.continuation.yield(())
            migrationTrigger.continuation.finish()
        }
    }

    func waitForMigrationTrigger() async -> Bool {
        var iterator = migrationTrigger.stream.makeAsyncIterator()
        return await iterator.next() != nil
    }

    func finishMigrationTriggerWait() {
        migrationTrigger.continuation.finish()
    }

    func snapshot() -> OptionalMigrationLocalSaveTraceSnapshot {
        lock.withLock {
            OptionalMigrationLocalSaveTraceSnapshot(
                events: events,
                writerIdentityCount: writerIdentities.count
            )
        }
    }

    private func isMigrationTriggerStatement(_ sql: String) -> Bool {
        let normalizedSQL = sql.uppercased()
        switch schemaState {
        case .fresh:
            return normalizedSQL.contains("CREATE TABLE SESSIONS_CONVERSATION")
        case .steady:
            return normalizedSQL.contains("CREATE TABLE IF NOT EXISTS GRDB_MIGRATIONS")
        }
    }
}

private enum OptionalMigrationLocalSaveTraceEvent: Sendable {
    case statement(
        instant: ContinuousClock.Instant,
        writerIdentity: ObjectIdentifier,
        sql: String
    )
    case profile(
        instant: ContinuousClock.Instant,
        writerIdentity: ObjectIdentifier,
        sql: String,
        durationMilliseconds: Double
    )

    var sql: String {
        switch self {
        case .statement(_, _, let sql), .profile(_, _, let sql, _):
            return sql
        }
    }

    var instant: ContinuousClock.Instant {
        switch self {
        case .statement(let instant, _, _), .profile(let instant, _, _, _):
            return instant
        }
    }
}

private struct OptionalMigrationLocalSaveTraceSnapshot {
    let events: [OptionalMigrationLocalSaveTraceEvent]
    let writerIdentityCount: Int

    func requireMigrationTrace() throws -> CategorizedSQLTrace {
        try categorizedTrace(matching: isMigrationSQL)
    }

    func requireLocalSaveTrace() throws -> CategorizedSQLTrace {
        try categorizedTrace(matching: isLocalSaveSQL)
    }

    private func categorizedTrace(
        matching predicate: (String) -> Bool
    ) throws -> CategorizedSQLTrace {
        let matchingEvents = events.filter { predicate($0.sql) }
        let statements = matchingEvents.compactMap { event -> ContinuousClock.Instant? in
            guard case .statement(let instant, _, _) = event else { return nil }
            return instant
        }
        let profiles = matchingEvents.compactMap { event -> (ContinuousClock.Instant, Double)? in
            guard case .profile(let instant, _, _, let durationMilliseconds) = event else {
                return nil
            }
            return (instant, durationMilliseconds)
        }
        guard let firstStatementInstant = statements.first,
            let lastProfileInstant = profiles.last?.0
        else {
            throw OptionalMigrationMeasurementError.missingCategorizedTrace
        }
        return CategorizedSQLTrace(
            firstStatementInstant: firstStatementInstant,
            lastProfileInstant: lastProfileInstant,
            profileDurationMilliseconds: profiles.reduce(0) { $0 + $1.1 },
            statementCount: statements.count
        )
    }
}

private struct CategorizedSQLTrace {
    let firstStatementInstant: ContinuousClock.Instant
    let lastProfileInstant: ContinuousClock.Instant
    let profileDurationMilliseconds: Double
    let statementCount: Int
}

private final class LocalSaveSynchronousCallTiming: @unchecked Sendable {
    private let clock: ContinuousClock
    private let lock = NSLock()
    private var interval: (start: ContinuousClock.Instant, end: ContinuousClock.Instant)?

    init(clock: ContinuousClock) {
        self.clock = clock
    }

    func measure(_ operation: () throws -> Void) throws {
        let start = clock.now
        do {
            try operation()
            lock.withLock {
                interval = (start, clock.now)
            }
        } catch {
            lock.withLock {
                interval = (start, clock.now)
            }
            throw error
        }
    }

    func requiredInterval() throws -> (start: ContinuousClock.Instant, end: ContinuousClock.Instant) {
        guard let interval = lock.withLock({ interval }) else {
            throw OptionalMigrationMeasurementError.missingLocalSaveTiming
        }
        return interval
    }
}

private struct LocalSaveTaskTiming {
    let submissionInstant: ContinuousClock.Instant
    let actorCallCompletionInstant: ContinuousClock.Instant
    let synchronousCallInterval: (start: ContinuousClock.Instant, end: ContinuousClock.Instant)
}

private struct OptionalMigrationLocalSaveSampleReport: Codable {
    let sampleIndex: Int
    let overlapCategory: String
    let migrationCallUpperBoundMilliseconds: Double
    let migrationSQLComponentMilliseconds: Double
    let migrationSQLEnvelopeMilliseconds: Double
    let saveSubmissionToFirstSQLAdmissionUpperBoundMilliseconds: Double
    let localRepositorySynchronousCallMilliseconds: Double
    let localSaveActorCallMilliseconds: Double
    let migrationStatementCount: Int
    let localSaveStatementCount: Int
    let writerIdentityCount: Int
}

private struct OptionalMigrationLocalSaveMeasurementReport: Codable {
    let schemaState: String
    let sampleCount: Int
    let tracedSQLOverlapSampleCount: Int
    let nonOverlapSampleCount: Int
    let samples: [OptionalMigrationLocalSaveSampleReport]
}

private func printMeasurementReport(
    schemaState: OptionalMigrationSchemaState,
    samples: [OptionalMigrationLocalSaveSampleReport]
) {
    let overlapSampleCount = samples.count { $0.overlapCategory == "traced_sql_overlap" }
    let report = OptionalMigrationLocalSaveMeasurementReport(
        schemaState: schemaState.rawValue,
        sampleCount: samples.count,
        tracedSQLOverlapSampleCount: overlapSampleCount,
        nonOverlapSampleCount: samples.count - overlapSampleCount,
        samples: samples
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(report),
        let json = String(data: data, encoding: .utf8)
    else {
        Issue.record("Could not encode optional migration measurement report")
        return
    }
    print("V10_OPTIONAL_MIGRATION_LOCAL_SAVE_MEASUREMENT \(json)")
}

private func isMigrationSQL(_ sql: String) -> Bool {
    let normalizedSQL = sql.uppercased()
    return normalizedSQL.contains("GRDB_MIGRATIONS")
        || normalizedSQL.contains("SESSIONS_")
        || normalizedSQL.contains("LOCAL_IPC_CREDENTIAL")
        || normalizedSQL.contains("LOCAL_PANE_CREDENTIAL_RECORD")
}

private func isLocalSaveSQL(_ sql: String) -> Bool {
    let normalizedSQL = sql.uppercased()
    return normalizedSQL.contains("LOCAL_WINDOW_STATE")
        || normalizedSQL.contains("LOCAL_WORKSPACE_CURSOR")
        || normalizedSQL.contains("LOCAL_TAB_CURSOR")
        || normalizedSQL.contains("LOCAL_ARRANGEMENT_CURSOR")
        || normalizedSQL.contains("LOCAL_DRAWER_CURSOR")
        || normalizedSQL.contains("LOCAL_ARRANGEMENT_DRAWER_CURSOR")
}

private func milliseconds(from duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1000
        + Double(components.attoseconds) / 1e15
}

private enum OptionalMigrationMeasurementError: Error {
    case optionalMigrationUnavailable
    case missingMigrationTrigger
    case missingCategorizedTrace
    case missingLocalSaveTiming
}

private let expectedLocalMigrationIdentifiers = [
    "001_create_application_local_schema",
    "002_replace_recent_targets_with_entity_recency",
    "003_invert_sidebar_group_memory",
    "004_remove_persisted_pull_request_counts",
    "005_move_repo_grouping_to_window_sidebar_memory",
    "006_add_repository_local_activity_facts",
    "006_create_worktree_annotation_schema",
    "007_add_worktree_annotation_message_handled",
    "008_add_worktree_annotation_message_viewed_revision",
    "009_add_worktree_annotation_reviewed_subject_evidence",
    "010_remove_worktree_annotation_workspace_provenance",
    "007_add_per_screen_sidebar_organization",
    "011_create_sessions_ingestion_schema",
    "012_create_ipc_credential_schema",
    "013_create_opaque_pane_credential_records",
]
