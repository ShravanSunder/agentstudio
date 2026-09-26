import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@MainActor
@Suite("WorkspaceSQLiteDatastoreActorTests", .serialized)
struct WorkspaceSQLiteDatastoreActorTests {
    @Test("workspace save runs through datastore actor probe")
    func workspaceSaveRunsThroughDatastoreActorProbe() async throws {
        let workspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let recorder = DatastoreProbeRecorder()
        let preparedApplicationLocalRepository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: localQueue
        )
        let datastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            preparedApplicationLocalRepository: preparedApplicationLocalRepository,
            probe: { event in await recorder.record(event) }
        )

        try await datastore.saveWorkspaceSnapshotBundle(
            .emptyTopologyFixture(
                workspace: .emptyFixture(
                    id: workspaceId,
                    name: "Datastore",
                    updatedAt: Date(timeIntervalSince1970: 2)
                )
            )
        )

        #expect(await recorder.events.contains(.saveWorkspaceSnapshot))
    }

    @Test("one datastore saves two workspaces and restores the last selected workspace")
    func oneDatastoreSavesAndRestoresTwoWorkspaces() async throws {
        let firstWorkspaceId = UUIDv7.generate()
        let secondWorkspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.multiple-workspaces.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.multiple-workspaces.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let preparedApplicationLocalRepository = WorkspaceLocalRepository(
            workspaceId: firstWorkspaceId,
            databaseWriter: localQueue
        )
        let datastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            preparedApplicationLocalRepository: preparedApplicationLocalRepository
        )
        _ = await datastore.loadWorkspaceSnapshot()

        try await datastore.saveWorkspaceSnapshotBundle(
            .emptyTopologyFixture(
                workspace: .emptyFixture(
                    id: firstWorkspaceId,
                    name: "First Workspace",
                    updatedAt: Date(timeIntervalSince1970: 10)
                )
            )
        )
        try await datastore.saveWorkspaceSnapshotBundle(
            .emptyTopologyFixture(
                workspace: .emptyFixture(
                    id: secondWorkspaceId,
                    name: "Second Workspace",
                    updatedAt: Date(timeIntervalSince1970: 20)
                )
            )
        )

        let restoredWorkspaceResult = await datastore.loadWorkspaceSnapshot()
        guard case .loaded(let restoredWorkspace) = restoredWorkspaceResult else {
            Issue.record("Expected the last saved workspace to restore, got \(restoredWorkspaceResult)")
            return
        }
        #expect(restoredWorkspace.id == secondWorkspaceId)
        #expect(restoredWorkspace.name == "Second Workspace")

        let persistedWorkspaceRecords = try coreRepository.fetchWorkspaces()
        #expect(persistedWorkspaceRecords.count == 2)

        let persistedFirstWorkspace = try coreRepository.fetchWorkspace(id: firstWorkspaceId)
        #expect(persistedFirstWorkspace?.id == firstWorkspaceId)
        #expect(persistedFirstWorkspace?.name == "First Workspace")

        let persistedSecondWorkspace = try coreRepository.fetchWorkspace(id: secondWorkspaceId)
        #expect(persistedSecondWorkspace?.id == secondWorkspaceId)
        #expect(persistedSecondWorkspace?.name == "Second Workspace")
    }

    @Test("workspace save emits persistence operation trace records")
    func workspaceSaveEmitsPersistenceOperationTraceRecords() async throws {
        let workspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.trace.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.trace.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let traceRuntime = makePersistenceTraceRuntime(tags: "persistence.operation")
        let preparedApplicationLocalRepository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: localQueue
        )
        let datastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            preparedApplicationLocalRepository: preparedApplicationLocalRepository,
            traceRuntime: traceRuntime
        )

        try await datastore.saveWorkspaceSnapshotBundle(
            .emptyTopologyFixture(workspace: .emptyFixture(id: workspaceId, name: "Trace Save"))
        )
        try await traceRuntime.flush()

        let contents = try persistenceTraceContents(from: traceRuntime)
        #expect(contents.contains("\"agentstudio.trace.tag\":\"persistence.operation\""))
        #expect(contents.contains("\"agentstudio.persistence.operation\":\"workspace.save\""))
        #expect(contents.contains("\"agentstudio.persistence.phase\":\"write_local\""))
        #expect(contents.contains("\"agentstudio.persistence.phase\":\"commit_core\""))
        #expect(contents.contains("\"agentstudio.persistence.outcome\":\"succeeded\""))
        #expect(contents.contains("\"agentstudio.workspace.id\":\"\(workspaceId.uuidString)\""))
        #expect(!contents.contains("\"agentstudio.trace.tag\":\"persistence.recovery\""))
    }

    @Test("workspace save validation failure emits persistence recovery trace")
    func workspaceSaveValidationFailureEmitsPersistenceRecoveryTrace() async throws {
        let workspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.save-failure-trace.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.save-failure-trace.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let traceRuntime = makePersistenceTraceRuntime(tags: "persistence.recovery,persistence.snapshot")
        let preparedApplicationLocalRepository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: localQueue
        )
        let datastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            preparedApplicationLocalRepository: preparedApplicationLocalRepository,
            traceRuntime: traceRuntime
        )

        do {
            try await datastore.saveWorkspaceSnapshotBundle(
                .emptyTopologyFixture(
                    workspace: .snapshotWithArrangementPaneMissingFromTab(workspaceId: workspaceId)
                )
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

    @Test("workspace save local open failure preserves committed core and emits local recovery trace")
    func workspaceSaveLocalOpenFailurePreservesCommittedCoreAndEmitsLocalRecoveryTrace() async throws {
        let workspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.local-open-failure-trace.core")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        let traceRuntime = makePersistenceTraceRuntime(tags: "persistence.recovery,persistence.snapshot")
        let recorder = DatastoreProbeRecorder()
        let localUnavailableFailure = WorkspaceSQLiteDatastoreFailure(CocoaError(.fileNoSuchFile))
        let datastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            localUnavailable: localUnavailableFailure,
            traceRuntime: traceRuntime,
            probe: { event in await recorder.record(event) }
        )

        await #expect(throws: localUnavailableFailure) {
            try await datastore.saveWorkspaceSnapshotBundle(
                .emptyTopologyFixture(workspace: .emptyFixture(id: workspaceId, name: "Local Open Failure"))
            )
        }
        try await traceRuntime.flush()

        guard
            case .loaded(let authoritativeSnapshot) = try WorkspaceCoreRepository(
                databaseWriter: coreQueue
            ).fetchAuthoritativeSnapshot()
        else {
            Issue.record("Expected the core commit to remain authoritative")
            return
        }
        #expect(authoritativeSnapshot.workspace.id == workspaceId)
        #expect(authoritativeSnapshot.workspace.name == "Local Open Failure")
        #expect(await recorder.events.contains(.saveWorkspaceSnapshotFailed))
        #expect(!(await recorder.events.contains(.saveWorkspaceSnapshotSucceeded)))
        let contents = try persistenceTraceContents(from: traceRuntime)
        #expect(!contents.contains("\"body\":\"persistence.snapshot.failed\""))
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
        let preparedApplicationLocalRepository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: localQueue
        )
        let datastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            preparedApplicationLocalRepository: preparedApplicationLocalRepository,
            traceRuntime: traceRuntime
        )

        try await datastore.saveWorkspaceSnapshotBundle(
            .emptyTopologyFixture(workspace: .emptyFixture(id: workspaceId, name: "Trace Cache Warmup"))
        )
        try await datastore.saveUIState(
            .init(
                filterText: "repos",
                isFilterVisible: true,
                sidebarCollapsed: false,
                sidebarSurface: .repos
            ),
            workspaceContextId: workspaceId
        )
        try await traceRuntime.flush()

        let contents = try persistenceTraceContents(from: traceRuntime)
        #expect(contents.contains("\"agentstudio.persistence.operation\":\"ui_state.save\""))
        #expect(contents.contains("\"agentstudio.persistence.phase\":\"write_local\""))
        #expect(contents.contains("\"agentstudio.persistence.outcome\":\"succeeded\""))
    }

    @Test("workspace snapshot bundle saves are serialized")
    func workspaceSnapshotBundleSavesAreSerialized() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.serial-save.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.serial-save.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let saveGate = DatastoreFirstSaveGate()
        let preparedApplicationLocalRepository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: localQueue
        )
        let datastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            preparedApplicationLocalRepository: preparedApplicationLocalRepository,
            probe: { event in
                guard event == .saveWorkspaceSnapshot else { return }
                await saveGate.pauseFirstSave()
            }
        )
        _ = await datastore.loadWorkspaceSnapshot()

        let firstSave = Task {
            try await datastore.saveWorkspaceSnapshotBundle(
                .emptyFixture(
                    id: workspaceId,
                    name: "Older Save",
                    updatedAt: Date(timeIntervalSince1970: 10)
                )
            )
        }
        await saveGate.waitUntilFirstSavePaused()
        let secondSave = Task {
            try await datastore.saveWorkspaceSnapshotBundle(
                .emptyFixture(
                    id: workspaceId,
                    name: "Newer Save",
                    updatedAt: Date(timeIntervalSince1970: 20)
                )
            )
        }

        await saveGate.releaseFirstSave()
        try await firstSave.value
        try await secondSave.value
        let loaded = await datastore.loadWorkspaceSnapshot()

        guard case .loaded(let snapshot) = loaded else {
            Issue.record("Expected loaded snapshot after serialized saves, got \(loaded)")
            return
        }
        #expect(snapshot.name == "Newer Save")
        #expect(snapshot.updatedAt == Date(timeIntervalSince1970: 20))
    }

    @Test("queued workspace snapshot bundle saves continue when prepared local is unavailable")
    func queuedWorkspaceSnapshotBundleSavesContinueWhenPreparedLocalIsUnavailable() async throws {
        let workspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.serial-save-failure.core")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        let saveGate = DatastoreFirstSaveGate()
        let localUnavailableFailure = WorkspaceSQLiteDatastoreFailure(CocoaError(.fileNoSuchFile))
        let datastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            localUnavailable: localUnavailableFailure,
            probe: { event in
                guard event == .saveWorkspaceSnapshot else { return }
                await saveGate.pauseFirstSave()
            }
        )
        _ = await datastore.loadWorkspaceSnapshot()

        let firstSave = Task {
            try await datastore.saveWorkspaceSnapshotBundle(
                .emptyFixture(
                    id: workspaceId,
                    name: "Failing Older Save",
                    updatedAt: Date(timeIntervalSince1970: 10)
                )
            )
        }
        await saveGate.waitUntilFirstSavePaused()
        let secondSave = Task {
            try await datastore.saveWorkspaceSnapshotBundle(
                .emptyFixture(
                    id: workspaceId,
                    name: "Recovered Newer Save",
                    updatedAt: Date(timeIntervalSince1970: 20)
                )
            )
        }

        await saveGate.releaseFirstSave()
        await #expect(throws: localUnavailableFailure) {
            try await firstSave.value
        }
        await #expect(throws: localUnavailableFailure) {
            try await secondSave.value
        }
        let loaded = await datastore.loadWorkspaceSnapshot()

        guard case .loaded(let snapshot) = loaded else {
            Issue.record("Expected loaded snapshot after queued failure recovery, got \(loaded)")
            return
        }
        #expect(snapshot.name == "Recovered Newer Save")
        #expect(snapshot.updatedAt == Date(timeIntervalSince1970: 20))
    }

    @Test("production datastore quarantines corrupt local SQLite before save")
    func productionDatastoreQuarantinesCorruptLocalSQLiteBeforeSave() async throws {
        let workspaceId = UUIDv7.generate()
        let rootDirectory = try makeDatastoreActorTemporaryDirectory(prefix: "local-save-quarantine")
        let coreSQLiteURL = rootDirectory.appending(path: "core.sqlite")
        let localSQLiteURL = rootDirectory.appending(path: "local.sqlite")
        let factory = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreSQLiteURL,
            localDatabaseURL: localSQLiteURL
        )
        let corePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: coreSQLiteURL,
            label: "AgentStudio.sqlite.datastore.local-save-quarantine.core-seed"
        )
        let localPool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: localSQLiteURL,
            label: "AgentStudio.sqlite.datastore.local-save-quarantine.local-seed"
        )
        try WorkspaceCoreMigrations.migrate(corePool)
        try WorkspaceLocalMigrations.migrate(localPool)
        try WorkspaceSQLiteStoreBackend(
            coreRepository: WorkspaceCoreRepository(databaseWriter: corePool),
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localPool)
            }
        ).save(.emptyTopologyFixture(workspace: .emptyFixture(id: workspaceId, name: "Before Corruption")))
        try corePool.close()
        try localPool.close()
        try Data("not a sqlite database".utf8).write(to: localSQLiteURL)
        let saveDatastore = factory.makeDatastore()
        let preparation = await saveDatastore.prepareDatabasesForBoot()
        guard case .prepared(let receipt) = preparation,
            case .available(recovery: .some) = receipt.local
        else {
            Issue.record("Expected corrupt local database to be replaced during preparation")
            return
        }
        _ = await saveDatastore.loadWorkspaceSnapshot()

        try await saveDatastore.saveWorkspaceSnapshotBundle(
            .emptyTopologyFixture(workspace: .emptyFixture(id: workspaceId, name: "Saved After Quarantine"))
        )
        let result = await saveDatastore.loadWorkspaceSnapshot()

        guard case .loaded(let snapshot) = result else {
            Issue.record("Expected loaded snapshot after local save quarantine, got \(result)")
            return
        }
        #expect(snapshot.name == "Saved After Quarantine")
        let quarantineArtifacts = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains("local.sqlite.corrupt-") }
        #expect(quarantineArtifacts.count == 1)
    }

}
private actor DatastoreProbeRecorder {
    private(set) var events: [WorkspaceSQLiteDatastoreActor.ProbeEvent] = []

    func record(_ event: WorkspaceSQLiteDatastoreActor.ProbeEvent) {
        events.append(event)
    }
}

private actor DatastoreFirstSaveGate {
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var pausedContinuation: CheckedContinuation<Void, Never>?
    private var didPause = false

    func pauseFirstSave() async {
        guard !didPause else { return }
        didPause = true
        await withCheckedContinuation { continuation in
            pauseContinuation = continuation
            pausedContinuation?.resume()
            pausedContinuation = nil
        }
    }

    func waitUntilFirstSavePaused() async {
        guard !didPause else { return }
        await withCheckedContinuation { continuation in
            pausedContinuation = continuation
        }
    }

    func releaseFirstSave() {
        pauseContinuation?.resume()
        pauseContinuation = nil
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
            "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
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
