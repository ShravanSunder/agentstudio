import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteDatastoreActorTests", .serialized)
struct WorkspaceSQLiteDatastoreActorTests {
    @Test("workspace save runs through datastore actor probe")
    func workspaceSaveRunsThroughDatastoreActorProbe() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let recorder = DatastoreProbeRecorder()
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) },
            probe: { event in await recorder.record(event) }
        )

        try await datastore.saveWorkspaceSnapshot(
            .emptyFixture(
                id: workspaceId,
                name: "Datastore",
                updatedAt: Date(timeIntervalSince1970: 2)
            )
        )

        #expect(await recorder.events.contains(.saveWorkspaceSnapshot))
        #expect(await recorder.events.contains(.localRepositoryOpened(workspaceId, .save)))
    }

    @Test("workspace save emits persistence operation trace records")
    func workspaceSaveEmitsPersistenceOperationTraceRecords() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.trace.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.trace.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let traceRuntime = makePersistenceTraceRuntime(tags: "persistence.operation")
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) },
            traceRuntime: traceRuntime
        )

        try await datastore.saveWorkspaceSnapshot(.emptyFixture(id: workspaceId, name: "Trace Save"))
        try await traceRuntime.flush()

        let contents = try persistenceTraceContents(from: traceRuntime)
        #expect(contents.contains("\"agentstudio.trace.tag\":\"persistence.operation\""))
        #expect(contents.contains("\"agentstudio.persistence.operation\":\"workspace.save\""))
        #expect(contents.contains("\"agentstudio.persistence.phase\":\"stage_core\""))
        #expect(contents.contains("\"agentstudio.persistence.phase\":\"write_local\""))
        #expect(contents.contains("\"agentstudio.persistence.phase\":\"commit_core\""))
        #expect(contents.contains("\"agentstudio.persistence.outcome\":\"succeeded\""))
        #expect(contents.contains("\"agentstudio.workspace.id\":\"\(workspaceId.uuidString)\""))
        #expect(!contents.contains("\"agentstudio.trace.tag\":\"persistence.recovery\""))
    }

    @Test("workspace save validation failure emits persistence recovery trace")
    func workspaceSaveValidationFailureEmitsPersistenceRecoveryTrace() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.save-failure-trace.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.save-failure-trace.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let traceRuntime = makePersistenceTraceRuntime(tags: "persistence.recovery,persistence.snapshot")
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) },
            traceRuntime: traceRuntime
        )

        do {
            try await datastore.saveWorkspaceSnapshot(
                .snapshotWithArrangementPaneMissingFromTab(workspaceId: workspaceId)
            )
            Issue.record("Expected workspace save validation failure")
        } catch {
            #expect(String(describing: error).contains("arrangementPaneMissingFromTab"))
        }
        try await traceRuntime.flush()

        let contents = try persistenceTraceContents(from: traceRuntime)
        #expect(contents.contains("\"body\":\"persistence.recovery.failed\""))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"persistence.recovery\""))
        #expect(contents.contains("\"body\":\"persistence.snapshot.failed\""))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"persistence.snapshot\""))
        #expect(contents.contains("\"agentstudio.persistence.operation\":\"workspace.save\""))
        #expect(contents.contains("\"agentstudio.persistence.phase\":\"commit_core\""))
        #expect(contents.contains("\"agentstudio.persistence.outcome\":\"failed\""))
        #expect(contents.contains("\"agentstudio.persistence.recovery.kind\":\"save_failed\""))
        #expect(contents.contains("\"agentstudio.workspace.snapshot.has_tab_membership_mismatch\":true"))
        #expect(contents.contains("\"agentstudio.workspace.snapshot.tab_membership_mismatches\""))
        #expect(contents.contains("\"agentstudio.persistence.error.description\""))
        #expect(contents.contains("arrangementPaneMissingFromTab"))
    }

    @Test("cached local repository saves still emit operation trace records")
    func cachedLocalRepositorySavesStillEmitOperationTraceRecords() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.cached-trace.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.cached-trace.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let traceRuntime = makePersistenceTraceRuntime(tags: "persistence.operation")
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) },
            traceRuntime: traceRuntime
        )

        try await datastore.saveWorkspaceSnapshot(.emptyFixture(id: workspaceId, name: "Trace Cache Warmup"))
        try await datastore.saveUIState(
            .init(
                filterText: "repos",
                isFilterVisible: true,
                sidebarCollapsed: false,
                sidebarSurface: .repos
            ),
            workspaceId: workspaceId
        )
        try await traceRuntime.flush()

        let contents = try persistenceTraceContents(from: traceRuntime)
        #expect(contents.contains("\"agentstudio.persistence.operation\":\"ui_state.save\""))
        #expect(contents.contains("\"agentstudio.persistence.phase\":\"write_local\""))
        #expect(contents.contains("\"agentstudio.persistence.outcome\":\"succeeded\""))
    }

    @Test("local repository is cached by workspace id across production saves")
    func localRepositoryIsCachedByWorkspaceIdAcrossProductionSaves() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.cache.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.cache.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let recorder = DatastoreProbeRecorder()
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
            },
            probe: { event in await recorder.record(event) }
        )

        try await datastore.saveWorkspaceSnapshot(.emptyFixture(id: workspaceId, name: "One"))
        try await datastore.saveWorkspaceSnapshot(.emptyFixture(id: workspaceId, name: "Two"))

        #expect(await recorder.events.filter { $0 == .localRepositoryOpened(workspaceId, .save) }.count == 1)
    }

    @Test("local repository is cached by workspace id across production load")
    func localRepositoryIsCachedByWorkspaceIdAcrossProductionLoad() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.load.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.load.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let recorder = DatastoreProbeRecorder()
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
            },
            probe: { event in await recorder.record(event) }
        )

        try await datastore.saveWorkspaceSnapshot(.emptyFixture(id: workspaceId, name: "Loaded"))
        _ = await datastore.loadWorkspaceSnapshot(preferredWorkspaceId: workspaceId)

        #expect(await recorder.events.filter { $0 == .localRepositoryOpened(workspaceId, .save) }.count == 1)
        #expect(await recorder.events.filter { $0 == .localRepositoryOpened(workspaceId, .restore) }.count == 1)
    }

    @Test("restore repair uses save repository cache")
    func restoreRepairUsesSaveRepositoryCache() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.repair.core")
        let seedLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.repair.seed")
        let staleRestoreLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.repair.restore")
        let repairLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.repair.save")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(seedLocalQueue)
        try WorkspaceLocalMigrations.migrate(staleRestoreLocalQueue)
        try WorkspaceLocalMigrations.migrate(repairLocalQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let seedBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: seedLocalQueue) }
        )
        let updatedAt = Date(timeIntervalSince1970: 3)
        try seedBackend.save(.emptyFixture(id: workspaceId, name: "Repair", updatedAt: updatedAt))
        let recorder = DatastoreProbeRecorder()
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: repairLocalQueue) },
            makeLocalRestoreRepository: {
                WorkspaceLocalRepository(workspaceId: $0, databaseWriter: staleRestoreLocalQueue)
            },
            probe: { event in await recorder.record(event) }
        )

        _ = await datastore.loadWorkspaceSnapshot(preferredWorkspaceId: workspaceId)

        #expect(await recorder.events.filter { $0 == .localRepositoryOpened(workspaceId, .restore) }.count == 1)
        #expect(await recorder.events.filter { $0 == .localRepositoryOpened(workspaceId, .save) }.count == 1)
        let repairedRepository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: repairLocalQueue)
        #expect(try repairedRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == updatedAt)
    }

    @Test("workspace load returns first local restore recovery events")
    func workspaceLoadReturnsFirstLocalRestoreRecoveryEvents() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.recovery.core")
        let seedLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.recovery.seed")
        let repairLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.recovery.repair")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(seedLocalQueue)
        try WorkspaceLocalMigrations.migrate(repairLocalQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let seedBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: seedLocalQueue) }
        )
        try seedBackend.save(.emptyFixture(id: workspaceId, name: "Recovered"))
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: repairLocalQueue) },
            makeLocalRestoreRepository: { workspaceId in
                throw WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption(workspaceId)
            }
        )

        let result = await datastore.loadWorkspaceSnapshot(preferredWorkspaceId: workspaceId)

        guard case .loaded(let snapshot, let recoveryEvents) = result else {
            Issue.record("Expected loaded snapshot after local recovery")
            return
        }
        #expect(snapshot.id == workspaceId)
        #expect(
            recoveryEvents.contains {
                $0.store == .workspace
                    && $0.workspaceId == workspaceId
                    && $0.recovery == .quarantinedAndReset
            }
        )
    }

    @Test("workspace status APIs use datastore boundary")
    func workspaceStatusApisUseDatastoreBoundary() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.status.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.status.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) }
        )

        #expect(await datastore.inspectWorkspaceRows() == .empty)
        try await datastore.saveWorkspaceSnapshot(.emptyFixture(id: workspaceId, name: "Status"))
        #expect(await datastore.inspectWorkspaceRows() == .hasWorkspaceRows)
        guard
            case .completed(true, let recoveryEvents) = await datastore.completedSnapshotStatus(
                workspaceId: workspaceId
            )
        else {
            Issue.record("Expected completed snapshot status")
            return
        }
        #expect(recoveryEvents.isEmpty)
        #expect(await datastore.legacyImportStatus(workspaceId: workspaceId) == .missing)
    }

    @Test("production datastore quarantines corrupt core SQLite before reporting uninitialized")
    func productionDatastoreQuarantinesCorruptCoreSQLiteBeforeReportingUninitialized() async throws {
        let rootDirectory = try makeDatastoreActorTemporaryDirectory(prefix: "core-quarantine")
        let coreSQLiteURL = rootDirectory.appending(path: "core.sqlite")
        try Data("not a sqlite database".utf8).write(to: coreSQLiteURL)
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreSQLiteURL,
            localDatabaseURL: { workspaceId in
                rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
            }
        ).makeDatastore()

        let result = await datastore.loadWorkspaceSnapshot(preferredWorkspaceId: UUID())

        guard case .uninitialized(let recoveryEvents) = result else {
            Issue.record("Expected uninitialized result after core quarantine, got \(result)")
            return
        }
        #expect(
            recoveryEvents.contains { event in
                event.store == .workspace
                    && event.workspaceId == nil
                    && event.recovery == .quarantinedAndReset
                    && event.quarantinedFilename?.contains("core.sqlite.corrupt-") == true
            },
            "Recovery events: \(recoveryEvents)"
        )
        #expect(FileManager.default.fileExists(atPath: coreSQLiteURL.path))
    }

    @Test("production datastore quarantines corrupt local SQLite and reports first restore event")
    func productionDatastoreQuarantinesCorruptLocalSQLiteAndReportsFirstRestoreEvent() async throws {
        let workspaceId = UUID()
        let rootDirectory = try makeDatastoreActorTemporaryDirectory(prefix: "local-quarantine")
        let coreSQLiteURL = rootDirectory.appending(path: "core.sqlite")
        let localSQLiteURL = rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
        let factory = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreSQLiteURL,
            localDatabaseURL: { _ in localSQLiteURL }
        )
        do {
            let seedDatastore = factory.makeDatastore()
            try await seedDatastore.saveWorkspaceSnapshot(
                .emptyFixture(id: workspaceId, name: "Local Quarantine")
            )
        }
        try Data("not a sqlite database".utf8).write(to: localSQLiteURL)
        let restoreDatastore = factory.makeDatastore()

        let result = await restoreDatastore.loadWorkspaceSnapshot(preferredWorkspaceId: workspaceId)

        guard case .loaded(let snapshot, let recoveryEvents) = result else {
            Issue.record("Expected loaded snapshot after local quarantine, got \(result)")
            return
        }
        #expect(snapshot.id == workspaceId)
        #expect(
            recoveryEvents.contains { event in
                event.store == .workspace
                    && event.workspaceId == workspaceId
                    && event.recovery == .quarantinedAndReset
                    && event.quarantinedFilename?.contains(".local.sqlite.corrupt-") == true
            },
            "Recovery events: \(recoveryEvents)"
        )
        #expect(FileManager.default.fileExists(atPath: localSQLiteURL.path))
    }

    @Test("production datastore emits persistence recovery trace for corrupt local SQLite")
    func productionDatastoreEmitsPersistenceRecoveryTraceForCorruptLocalSQLite() async throws {
        let workspaceId = UUID()
        let rootDirectory = try makeDatastoreActorTemporaryDirectory(prefix: "local-quarantine-trace")
        let coreSQLiteURL = rootDirectory.appending(path: "core.sqlite")
        let localSQLiteURL = rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
        let seedFactory = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreSQLiteURL,
            localDatabaseURL: { _ in localSQLiteURL }
        )
        try await seedFactory.makeDatastore().saveWorkspaceSnapshot(
            .emptyFixture(id: workspaceId, name: "Local Quarantine Trace")
        )
        try Data("not a sqlite database".utf8).write(to: localSQLiteURL)
        let traceRuntime = makePersistenceTraceRuntime(tags: "persistence.recovery")
        let restoreDatastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreSQLiteURL,
            localDatabaseURL: { _ in localSQLiteURL },
            traceRuntime: traceRuntime
        ).makeDatastore()

        _ = await restoreDatastore.loadWorkspaceSnapshot(preferredWorkspaceId: workspaceId)
        try await traceRuntime.flush()

        let contents = try persistenceTraceContents(from: traceRuntime)
        #expect(contents.contains("\"body\":\"persistence.recovery.quarantined\""))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"persistence.recovery\""))
        #expect(contents.contains("\"agentstudio.persistence.operation\":\"workspace.load\""))
        #expect(contents.contains("\"agentstudio.persistence.phase\":\"quarantine_sidecars\""))
        #expect(contents.contains("\"agentstudio.persistence.recovery.kind\":\"local_quarantine\""))
        #expect(contents.contains("\"agentstudio.workspace.id\":\"\(workspaceId.uuidString)\""))
        #expect(!contents.contains("\"agentstudio.trace.tag\":\"persistence.operation\""))
    }

    @Test("production datastore quarantines corrupt local SQLite before save")
    func productionDatastoreQuarantinesCorruptLocalSQLiteBeforeSave() async throws {
        let workspaceId = UUID()
        let rootDirectory = try makeDatastoreActorTemporaryDirectory(prefix: "local-save-quarantine")
        let coreSQLiteURL = rootDirectory.appending(path: "core.sqlite")
        let localSQLiteURL = rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
        let factory = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreSQLiteURL,
            localDatabaseURL: { _ in localSQLiteURL }
        )
        try await factory.makeDatastore().saveWorkspaceSnapshot(
            .emptyFixture(id: workspaceId, name: "Before Corruption")
        )
        try Data("not a sqlite database".utf8).write(to: localSQLiteURL)
        let saveDatastore = factory.makeDatastore()

        try await saveDatastore.saveWorkspaceSnapshot(
            .emptyFixture(id: workspaceId, name: "Saved After Quarantine")
        )
        let result = await saveDatastore.loadWorkspaceSnapshot(preferredWorkspaceId: workspaceId)

        guard case .loaded(let snapshot, let recoveryEvents) = result else {
            Issue.record("Expected loaded snapshot after local save quarantine, got \(result)")
            return
        }
        #expect(snapshot.name == "Saved After Quarantine")
        #expect(
            recoveryEvents.contains { event in
                event.store == .workspace
                    && event.workspaceId == workspaceId
                    && event.recovery == .quarantinedAndReset
                    && event.quarantinedFilename?.contains(".local.sqlite.corrupt-") == true
            },
            "Recovery events: \(recoveryEvents)"
        )
    }

    @Test("datastore recovers staged core graph when local save failed")
    func datastoreRecoversStagedCoreGraphWhenLocalSaveFailed() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.staged-recovery.core")
        let repairLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.staged-recovery.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(repairLocalQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let failingDatastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in throw CocoaError(.fileNoSuchFile) }
        )

        do {
            try await failingDatastore.saveWorkspaceSnapshot(
                .emptyFixture(
                    id: workspaceId,
                    name: "Staged For Actor Recovery",
                    updatedAt: Date(timeIntervalSince1970: 20)
                )
            )
            Issue.record("Expected local save failure")
        } catch is CocoaError {
        } catch {
            Issue.record("Expected CocoaError, got \(error)")
        }
        let recoveringDatastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: repairLocalQueue) }
        )

        let result = await recoveringDatastore.loadWorkspaceSnapshot(preferredWorkspaceId: workspaceId)

        guard case .loaded(let snapshot, let recoveryEvents) = result else {
            Issue.record("Expected staged core recovery, got \(result)")
            return
        }
        #expect(snapshot.name == "Staged For Actor Recovery")
        #expect(
            recoveryEvents.contains {
                $0.store == .workspace
                    && $0.workspaceId == workspaceId
                    && $0.recovery == .resetToDefaults
            }
        )
    }

    @Test("production datastore legacy lane decisions honor completed companion import status")
    func productionDatastoreLegacyLaneDecisionsHonorCompletedCompanionImportStatus() async throws {
        let workspaceId = UUID()
        let rootDirectory = try makeDatastoreActorTemporaryDirectory(prefix: "legacy-decision")
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: rootDirectory.appending(path: "core.sqlite"),
            localDatabaseURL: { workspaceId in
                rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
            }
        ).makeDatastore()
        try await datastore.saveImportedLegacySnapshot(
            .emptyFixture(id: workspaceId, name: "Imported"),
            sourceStatePath: "legacy/workspace.state.json"
        )
        try await datastore.markLegacyWorkspaceCompanionImportsCompleted(
            workspaceId: workspaceId,
            importedAt: Date(timeIntervalSince1970: 3)
        )

        #expect(
            await datastore.localLegacyImportDecision(workspaceId: workspaceId, lane: .local)
                == .found(.blockReplayAllowArchive)
        )
        #expect(
            await datastore.localLegacyImportDecision(workspaceId: workspaceId, lane: .cache)
                == .found(.blockReplayAllowArchive)
        )
    }
}

private actor DatastoreProbeRecorder {
    private(set) var events: [WorkspaceSQLiteDatastore.ProbeEvent] = []

    func record(_ event: WorkspaceSQLiteDatastore.ProbeEvent) {
        events.append(event)
    }
}

private func makeDatastoreActorTemporaryDirectory(prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "agentstudio-datastore-\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func makePersistenceTraceRuntime(tags: String) -> AgentStudioTraceRuntime {
    AgentStudioTraceRuntime(
        configuration: AgentStudioTraceConfiguration.from(environment: [
            "AGENTSTUDIO_TRACE_DIR": persistenceTraceDirectoryURL().path,
            "AGENTSTUDIO_TRACE_FLUSH": "immediate",
            "AGENTSTUDIO_TRACE_NAME": "sqlite-datastore",
            "AGENTSTUDIO_TRACE_TAGS": tags,
        ]),
        processIdentifier: 920,
        timeUnixNano: { 2000 }
    )
}

private func persistenceTraceContents(from traceRuntime: AgentStudioTraceRuntime) throws -> String {
    let outputFileURL = try #require(traceRuntime.outputFileURL)
    return try String(contentsOf: outputFileURL, encoding: .utf8)
}

private func persistenceTraceDirectoryURL() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentstudio-sqlite-datastore-trace-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
