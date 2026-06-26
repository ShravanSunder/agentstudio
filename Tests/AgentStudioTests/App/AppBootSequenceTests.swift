import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct AppBootSequenceTests {
    @Test("boot sequence exposes the architecture-ordered steps")
    func orderedStepsMatchesArchitectureContract() {
        #expect(
            WorkspaceBootSequence.orderedSteps == [
                .loadCanonicalStore,
                .loadCacheStore,
                .loadUIStore,
                .establishRuntimeBus,
                .startFilesystemActor,
                .startGitProjector,
                .startForgeActor,
                .startCacheCoordinator,
                .triggerInitialTopologySync,
                .armPersistenceObservation,
                .readyForReactiveSidebar,
            ])
    }

    @Test("boot runner executes all steps in declared order")
    func runExecutesOrderedSequence() {
        var recorded: [WorkspaceBootStep] = []
        WorkspaceBootSequence.run { step in
            recorded.append(step)
        }
        #expect(recorded == WorkspaceBootSequence.orderedSteps)
    }

    @Test("every boot step explains why it exists")
    func bootStepsDocumentTheirPurpose() {
        for step in WorkspaceBootSequence.orderedSteps {
            #expect(!step.purpose.isEmpty, "Missing boot purpose for \(step.rawValue)")
        }
    }

    @Test("boot observation step arms every autosaving persistence store")
    func bootObservationStepArmsEveryAutosavingPersistenceStore() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift"),
            encoding: .utf8
        )

        #expect(appDelegateSource.contains("case .armPersistenceObservation:"))
        #expect(appDelegateSource.contains("bootArmPersistenceObservation()"))
        #expect(appDelegateSource.contains("store.repositoryTopologyStore.startObserving()"))
        #expect(appDelegateSource.contains("repoCacheStore.startObserving()"))
        #expect(appDelegateSource.contains("sidebarCacheStore.startObserving()"))
        #expect(appDelegateSource.contains("uiStateStore.startObserving()"))
        #expect(appDelegateSource.contains("workspaceSettingsStore.startObserving()"))
        #expect(appDelegateSource.contains("assertBootPersistenceObservationArmed()"))
    }

    @Test("boot loads settings with UI-scoped persistence stores")
    func bootLoadsSettingsWithUIScopedPersistenceStores() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift"),
            encoding: .utf8
        )

        #expect(appDelegateSource.contains("workspaceSettingsStore = WorkspaceSettingsStore("))
        #expect(appDelegateSource.contains("workspaceSettingsStore.restore(for: store.identityAtom.workspaceId)"))
    }

    @Test("boot injects SQLite datastore into canonical stores")
    func bootInjectsSQLiteDatastoreIntoCanonicalStores() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift"),
            encoding: .utf8
        )
        let datastoreFactorySource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastoreFactory.swift"
            ),
            encoding: .utf8
        )

        #expect(!appDelegateSource.contains("traceRuntime = .fromEnvironment()"))
        #expect(appDelegateSource.contains("makeWorkspaceSQLiteDatastore(traceRuntime: traceRuntime)"))
        #expect(appDelegateSource.contains("sqliteDatastore: workspaceSQLiteDatastore"))
        #expect(appDelegateSource.contains("await store.restoreAsync()"))
        #expect(appDelegateSource.contains("await repoCacheStore.restoreAsync("))
        #expect(appDelegateSource.contains("await sidebarCacheStore.restoreAsync("))
        #expect(appDelegateSource.contains("await uiStateStore.restoreAsync("))
        #expect(!appDelegateSource.contains("workspaceSQLiteStoreBackend"))
        #expect(!appDelegateSource.contains("workspaceLocalSQLiteStoreBackend"))
        #expect(datastoreFactorySource.contains("WorkspaceSQLiteDatastoreConfiguration("))
        #expect(
            datastoreFactorySource.contains(
                "WorkspaceSQLiteDatastore(configuration: configuration, traceRuntime: traceRuntime)"
            )
        )
    }

    @Test("boot injects feature SQLite adapter into inbox notification store")
    func bootInjectsFeatureSQLiteAdapterIntoInboxNotificationStore() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate.swift"),
            encoding: .utf8
        )
        let inboxBootSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationBoot.swift"),
            encoding: .utf8
        )

        #expect(appDelegateSource.contains("var workspaceSQLiteDatastore: WorkspaceSQLiteDatastore?"))
        #expect(!appDelegateSource.contains("var workspaceLocalSQLiteStoreBackend"))
        #expect(!appDelegateSource.contains("var workspaceSQLiteStoreBackend"))
        #expect(appDelegateSource.contains("var canArchiveLegacyInboxFile = true"))
        #expect(inboxBootSource.contains("InboxNotificationSQLiteDatastoreAdapter("))
        #expect(inboxBootSource.contains("workspaceId: workspaceId"))
        #expect(inboxBootSource.contains("sqliteAdapter: sqliteAdapter"))
        #expect(inboxBootSource.contains("allowLegacyFilePersistence: sqliteBootDecision.allowLegacyFilePersistence"))
        #expect(inboxBootSource.contains("allowLegacyFileImport: sqliteBootDecision.allowLegacyFileImport"))
        #expect(!inboxBootSource.contains("workspaceLocalSQLiteStoreBackend"))
        #expect(inboxBootSource.contains("canArchiveLegacyInboxFileAfterBlockedImport"))
        #expect(inboxBootSource.contains("await adapter.bootDecision()"))
        #expect(inboxBootSource.contains("InboxNotificationLegacyArchiveReadiness.canArchiveLegacyFile("))
        #expect(!inboxBootSource.contains("InboxNotificationSQLiteRepository("))
        #expect(inboxBootSource.contains("hadLegacyInboxFile"))
        #expect(inboxBootSource.contains("canArchiveLegacyInboxFile"))
    }

    @Test("legacy inbox archive readiness requires actual materialization proof")
    func legacyInboxArchiveReadinessRequiresActualMaterializationProof() {
        #expect(
            !InboxNotificationLegacyArchiveReadiness.canArchiveLegacyFile(
                hadLegacyFile: true,
                didLoadStore: true,
                hasSQLiteRepository: true,
                hasWorkspaceLocalSQLiteBackend: true,
                loadOutcome: .sqliteSnapshot,
                canArchiveAfterBlockedImport: false
            )
        )
        #expect(
            InboxNotificationLegacyArchiveReadiness.canArchiveLegacyFile(
                hadLegacyFile: true,
                didLoadStore: true,
                hasSQLiteRepository: true,
                hasWorkspaceLocalSQLiteBackend: true,
                loadOutcome: .legacyFileImportedIntoSQLite,
                canArchiveAfterBlockedImport: false
            )
        )
        #expect(
            InboxNotificationLegacyArchiveReadiness.canArchiveLegacyFile(
                hadLegacyFile: true,
                didLoadStore: true,
                hasSQLiteRepository: true,
                hasWorkspaceLocalSQLiteBackend: true,
                loadOutcome: .materializedLegacySQLiteSnapshot,
                canArchiveAfterBlockedImport: false
            )
        )
        #expect(
            InboxNotificationLegacyArchiveReadiness.canArchiveLegacyFile(
                hadLegacyFile: true,
                didLoadStore: true,
                hasSQLiteRepository: true,
                hasWorkspaceLocalSQLiteBackend: true,
                loadOutcome: .sqliteSnapshot,
                canArchiveAfterBlockedImport: true
            )
        )
        #expect(
            InboxNotificationLegacyArchiveReadiness.canArchiveLegacyFile(
                hadLegacyFile: false,
                didLoadStore: false,
                hasSQLiteRepository: false,
                hasWorkspaceLocalSQLiteBackend: true,
                loadOutcome: nil,
                canArchiveAfterBlockedImport: false
            )
        )
    }

    @Test("boot archive coordinator marks companion imports before archiving legacy workspace files")
    func bootArchiveCoordinatorMarksCompanionImportsBeforeArchivingLegacyWorkspaceFiles() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.boot.archive.core")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let localRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: localRoot, withIntermediateDirectories: true)
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { workspaceId in
                let localURL = localRoot.appending(path: "\(workspaceId.uuidString).local.sqlite")
                let localPool = try SQLiteDatabaseFactory.makeFileBackedPool(
                    at: localURL,
                    label: "AgentStudio.boot.archive.local.\(workspaceId.uuidString)"
                )
                try WorkspaceLocalMigrations.migrate(localPool)
                return WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localPool)
            }
        )
        try await datastore.saveWorkspaceSnapshot(
            .emptyFixture(
                id: workspaceId,
                name: "Archive Ready",
                updatedAt: Date(timeIntervalSince1970: 1_700_004_000)
            )
        )
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        #expect(persistor.ensureDirectory())
        try persistor.save(.init(id: workspaceId, name: "Legacy Archive Candidate"))
        try persistor.saveCache(.init(workspaceId: workspaceId))
        try persistor.saveUI(.init(workspaceId: workspaceId))
        try persistor.saveSidebarCache(.init(workspaceId: workspaceId))
        try coreRepository.markLegacyWorkspaceCoreImported(
            workspaceId: workspaceId,
            sourceStatePath: persistor.canonicalWorkspaceStatePath(for: workspaceId),
            importedAt: Date(timeIntervalSince1970: 1_700_004_005)
        )

        let archiveResult = await WorkspaceLegacyArchiveCoordinator.archiveLegacyWorkspaceFilesIfReady(
            workspaceId: workspaceId,
            persistor: persistor,
            sqliteDatastore: datastore,
            canArchiveLegacyCompanionFiles: true,
            now: { Date(timeIntervalSince1970: 1_700_004_010) }
        )

        guard case .archived = archiveResult.outcome else {
            Issue.record("Expected legacy workspace files to archive, got \(archiveResult.outcome)")
            return
        }
        #expect(archiveResult.recoveryEvents.isEmpty)
        let importStatus = try #require(
            try coreRepository.fetchLegacyWorkspaceImportStatus(workspaceId: workspaceId))
        #expect(importStatus.settingsImportedAt != nil)
        #expect(importStatus.localImportedAt != nil)
        #expect(importStatus.cacheImportedAt != nil)
        #expect(importStatus.archivedAt != nil)
        #expect(!persistor.hasLegacyWorkspaceFiles(for: workspaceId))
    }

    @Test("boot archive coordinator returns local recovery events discovered during readiness")
    func bootArchiveCoordinatorReturnsLocalRecoveryEventsDiscoveredDuringReadiness() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.boot.archive.recovery.core")
        let seedLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.boot.archive.recovery.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(seedLocalQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let seedBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: seedLocalQueue) }
        )
        try seedBackend.save(.emptyFixture(id: workspaceId, name: "Archive Recovery"))
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: seedLocalQueue) },
            makeLocalRestoreRepository: { workspaceId in
                throw WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption(
                    workspaceId,
                    quarantinedFilename: "\(workspaceId.uuidString).local.sqlite.corrupt-test"
                )
            }
        )
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        #expect(persistor.ensureDirectory())
        try persistor.save(.init(id: workspaceId, name: "Legacy Archive Candidate"))

        let archiveResult = await WorkspaceLegacyArchiveCoordinator.archiveLegacyWorkspaceFilesIfReady(
            workspaceId: workspaceId,
            persistor: persistor,
            sqliteDatastore: datastore,
            canArchiveLegacyCompanionFiles: true
        )

        #expect(archiveResult.outcome == .skipped(.notReady))
        #expect(
            archiveResult.recoveryEvents.contains { event in
                event.store == .workspace
                    && event.workspaceId == workspaceId
                    && event.recovery == .quarantinedAndReset
                    && event.quarantinedFilename?.contains(".local.sqlite.corrupt-test") == true
            },
            "Recovery events: \(archiveResult.recoveryEvents)"
        )
    }

    @Test("legacy workspace archive readiness requires completed SQLite and companion import proof")
    func legacyWorkspaceArchiveReadinessRequiresCompletedSQLiteAndCompanionImportProof() {
        #expect(
            WorkspaceLegacyArchiveReadiness.canArchiveLegacyFiles(
                hasSQLiteBackend: true,
                hasCompletedSnapshot: true,
                hasLegacyWorkspaceFiles: true,
                canArchiveLegacyCompanionFiles: true
            )
        )
        #expect(
            !WorkspaceLegacyArchiveReadiness.canArchiveLegacyFiles(
                hasSQLiteBackend: false,
                hasCompletedSnapshot: true,
                hasLegacyWorkspaceFiles: true,
                canArchiveLegacyCompanionFiles: true
            )
        )
        #expect(
            !WorkspaceLegacyArchiveReadiness.canArchiveLegacyFiles(
                hasSQLiteBackend: true,
                hasCompletedSnapshot: false,
                hasLegacyWorkspaceFiles: true,
                canArchiveLegacyCompanionFiles: true
            )
        )
        #expect(
            !WorkspaceLegacyArchiveReadiness.canArchiveLegacyFiles(
                hasSQLiteBackend: true,
                hasCompletedSnapshot: true,
                hasLegacyWorkspaceFiles: false,
                canArchiveLegacyCompanionFiles: true
            )
        )
        #expect(
            !WorkspaceLegacyArchiveReadiness.canArchiveLegacyFiles(
                hasSQLiteBackend: true,
                hasCompletedSnapshot: true,
                hasLegacyWorkspaceFiles: true,
                canArchiveLegacyCompanionFiles: false
            )
        )
    }

    @Test("termination flushes settings before shutdown completes")
    func terminationFlushesSettingsBeforeShutdownCompletes() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let terminationSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate+Termination.swift"),
            encoding: .utf8
        )

        #expect(terminationSource.contains("workspaceSettingsStore.flush(for: store.identityAtom.workspaceId)"))
    }

    @Test("inbox notification autosave observes memory, not runtime handoff state")
    func inboxNotificationAutosaveObservesMemoryNotRuntimeHandoffState() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let inboxBootSourceURL = projectRoot.appending(
            path: "Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationBoot.swift"
        )
        let appDelegateSource = try String(
            contentsOf: inboxBootSourceURL,
            encoding: .utf8
        )

        #expect(appDelegateSource.contains("_ = atomStore.inboxSidebarState.collapsedGroups"))
        #expect(!appDelegateSource.contains("_ = atomStore.inboxNotificationPrefs.grouping"))
        #expect(!appDelegateSource.contains("_ = atomStore.inboxNotificationPrefs.sort"))
        #expect(!appDelegateSource.contains("_ = atomStore.inboxNotificationPrefs.bellEnabled"))
        #expect(!appDelegateSource.contains("pendingFilter"))
        #expect(!appDelegateSource.contains("peekPendingFilter"))
        #expect(!appDelegateSource.contains("consumePendingFilter"))
    }

    @Test("production code avoids generic clock-based sleep overloads")
    func productionCodeAvoidsGenericClockBasedSleep() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourceRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let sourceFiles =
            FileManager.default
            .enumerator(at: sourceRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        var offenders: [String] = []

        for sourceFile in sourceFiles {
            let relativePath = sourceFile.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            guard relativePath != "Sources/AgentStudio/Infrastructure/Extensions/FoundationExtensions.swift" else {
                continue
            }
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for (lineIndex, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where Self.isGenericClockSleep(line) {
                offenders.append("\(relativePath):\(lineIndex + 1): \(line)")
            }
        }

        #expect(
            offenders.isEmpty,
            """
            macOS 26.4 release startup reproduced swift_task_dealloc crashes in the \
            generic clock-based sleep path. Use Duration.nanosecondsForTaskSleep \
            with Task.sleep(nanoseconds:) for production sleeps instead.

            \(offenders.joined(separator: "\n"))
            """
        )
    }

    private static func isGenericClockSleep(_ line: Substring) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard !trimmedLine.hasPrefix("//") else { return false }
        return trimmedLine.contains("Task.sleep(for:")
            || trimmedLine.contains(".sleep(for:")
    }
}
