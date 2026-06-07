import Foundation
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

    @Test("boot injects SQLite workspace backend into canonical store")
    func bootInjectsSQLiteWorkspaceBackendIntoCanonicalStore() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift"),
            encoding: .utf8
        )
        let backendFactorySource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackendFactory.swift"
            ),
            encoding: .utf8
        )

        #expect(appDelegateSource.contains("makeWorkspaceSQLiteStoreBackend()"))
        #expect(
            appDelegateSource.contains("workspaceLocalSQLiteStoreBackend = workspaceSQLiteStoreBackend?.localBackend"))
        #expect(appDelegateSource.contains("sqliteBackend: workspaceSQLiteStoreBackend"))
        #expect(appDelegateSource.contains("sqliteBackend: workspaceLocalSQLiteStoreBackend"))
        #expect(appDelegateSource.contains("WorkspaceSQLiteStoreBackendFactory("))
        #expect(backendFactorySource.contains("SQLiteDatabaseFactory.makeFileBackedPool("))
        #expect(backendFactorySource.contains("WorkspaceCoreRepository(databaseWriter: coreDatabasePool)"))
        #expect(backendFactorySource.contains("WorkspaceLocalRepository("))
        #expect(backendFactorySource.contains("workspaceId: workspaceId,"))
        #expect(backendFactorySource.contains("databaseWriter: localDatabasePool"))
        #expect(backendFactorySource.contains("try coreRepository.migrate()"))
        #expect(backendFactorySource.contains("try localRepository.migrate()"))
        #expect(backendFactorySource.contains("SQLiteSidecarQuarantine.quarantine("))
        #expect(backendFactorySource.contains("legacyImportDecision:"))
    }

    @Test("boot injects SQLite repository into inbox notification store")
    func bootInjectsSQLiteRepositoryIntoInboxNotificationStore() throws {
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

        #expect(appDelegateSource.contains("var workspaceLocalSQLiteStoreBackend: WorkspaceLocalSQLiteStoreBackend?"))
        #expect(appDelegateSource.contains("var workspaceSQLiteStoreBackend: WorkspaceSQLiteStoreBackend?"))
        #expect(appDelegateSource.contains("var canArchiveLegacyInboxFile = true"))
        #expect(inboxBootSource.contains("makeInboxNotificationSQLiteRepository("))
        #expect(inboxBootSource.contains("workspaceId: workspaceId"))
        #expect(inboxBootSource.contains("sqliteRepository: sqliteBootDecision.repository"))
        #expect(inboxBootSource.contains("allowLegacyFilePersistence: sqliteBootDecision.allowLegacyFilePersistence"))
        #expect(inboxBootSource.contains("allowLegacyFileImport: sqliteBootDecision.allowLegacyFileImport"))
        #expect(inboxBootSource.contains("workspaceLocalSQLiteStoreBackend.restoreRepository("))
        #expect(inboxBootSource.contains("workspaceLocalSQLiteStoreBackend.legacyImportDecision("))
        #expect(inboxBootSource.contains("canArchiveLegacyInboxFileAfterBlockedImport"))
        #expect(inboxBootSource.contains("hasMaterializedLegacyImport()"))
        #expect(inboxBootSource.contains("legacyImportDecision.canArchiveLegacyFile"))
        #expect(inboxBootSource.contains("&& hasMaterializedLegacyInboxImport"))
        #expect(inboxBootSource.contains("InboxNotificationSQLiteRepository("))
        #expect(inboxBootSource.contains("databaseWriter: localRepository.databaseWriter"))
        #expect(inboxBootSource.contains("allowLegacyFilePersistence: false"))
        #expect(inboxBootSource.contains("allowLegacyFileImport: false"))
        #expect(inboxBootSource.contains("hadLegacyInboxFile"))
        #expect(inboxBootSource.contains("canArchiveLegacyInboxFile"))
    }

    @Test("boot archives legacy workspace files after SQLite-backed stores load")
    func bootArchivesLegacyWorkspaceFilesAfterSQLiteBackedStoresLoad() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let bootSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift"),
            encoding: .utf8
        )

        #expect(bootSource.contains("bootArchiveLegacyWorkspaceFilesIfNeeded(persistor: persistor)"))
        #expect(bootSource.contains("guard let workspaceSQLiteStoreBackend else { return }"))
        #expect(
            bootSource.contains(
                "workspaceSQLiteStoreBackend.hasCompletedSnapshot(workspaceId: store.identityAtom.workspaceId)"))
        #expect(bootSource.contains("guard canArchiveLegacyCompanionFiles else"))
        #expect(bootSource.contains("repoCacheStore.canArchiveLegacyCacheFile"))
        #expect(bootSource.contains("sidebarCacheStore.canArchiveLegacySidebarCacheFile"))
        #expect(bootSource.contains("uiStateStore.canArchiveLegacyUIFile"))
        #expect(bootSource.contains("workspaceSettingsStore.canArchiveLegacySettingsFiles"))
        #expect(bootSource.contains("canArchiveLegacyInboxFile"))
        #expect(
            bootSource.contains(
                "workspaceSQLiteStoreBackend.markLegacyWorkspaceCompanionImportsCompleted("))
        #expect(bootSource.contains("workspaceSQLiteStoreBackend.markLegacyWorkspaceArchived("))
        let uiLoadRange = try #require(bootSource.range(of: "bootLoadInboxNotificationStore(persistor: persistor)"))
        let archiveRange = try #require(
            bootSource.range(of: "bootArchiveLegacyWorkspaceFilesIfNeeded(persistor: persistor)")
        )
        #expect(uiLoadRange.upperBound < archiveRange.lowerBound)

        let companionStatusRange = try #require(
            bootSource.range(of: "workspaceSQLiteStoreBackend.markLegacyWorkspaceCompanionImportsCompleted(")
        )
        let archiveFilesRange = try #require(
            bootSource.range(of: "persistor.archiveLegacyWorkspaceFiles(for: store.identityAtom.workspaceId)")
        )
        #expect(companionStatusRange.upperBound < archiveFilesRange.lowerBound)
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

    @Test("production code avoids the clock-based Task.sleep overload")
    func productionCodeAvoidsClockBasedTaskSleep() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourceRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let sourceFiles =
            FileManager.default
            .enumerator(at: sourceRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        var offenders: [String] = []

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for (lineIndex, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("Task.sleep(for:") {
                let relativePath = sourceFile.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
                offenders.append("\(relativePath):\(lineIndex + 1): \(line)")
            }
        }

        #expect(
            offenders.isEmpty,
            """
            macOS 26.4 release startup reproduced swift_task_dealloc crashes in the \
            generic clock-based Task.sleep overload. Use Duration.nanosecondsForTaskSleep \
            with Task.sleep(nanoseconds:) instead.

            \(offenders.joined(separator: "\n"))
            """
        )
    }
}
