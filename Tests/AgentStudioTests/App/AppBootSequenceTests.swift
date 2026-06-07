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

        #expect(appDelegateSource.contains("makeWorkspaceSQLiteStoreBackend()"))
        #expect(appDelegateSource.contains("sqliteBackend: workspaceSQLiteStoreBackend"))
        #expect(appDelegateSource.contains("WorkspaceCoreRepository(databaseWriter: coreDatabasePool)"))
        #expect(appDelegateSource.contains("WorkspaceLocalRepository("))
        #expect(appDelegateSource.contains("workspaceId: workspaceId,"))
        #expect(appDelegateSource.contains("databaseWriter: localDatabasePool"))
        #expect(appDelegateSource.contains("try coreRepository.migrate()"))
        #expect(appDelegateSource.contains("try localRepository.migrate()"))
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
