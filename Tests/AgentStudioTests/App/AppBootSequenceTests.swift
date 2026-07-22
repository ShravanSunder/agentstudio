import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct AppBootSequenceTests {
    @Test("boot sequence exposes only composition prerequisites before presentation")
    func presentationPrerequisitesMatchArchitectureContract() {
        #expect(
            WorkspaceBootSequence.presentationPrerequisiteSteps == [
                .loadCanonicalStore,
                .establishRuntimeBus,
            ])
        #expect(
            WorkspaceBootSequence.postPresentationSteps == [
                .loadCacheStore,
                .loadUIStore,
                .startFilesystemActor,
                .startGitProjector,
                .startForgeActor,
                .startCacheCoordinator,
                .triggerInitialTopologySync,
                .armPersistenceObservation,
                .readyForReactiveSidebar,
                .checkWorktrunkDependency,
            ])
    }

    @Test("presentation runner cannot execute post-presentation work")
    func presentationRunnerExecutesOnlyPrerequisites() {
        var recorded: [WorkspaceBootStep] = []
        WorkspaceBootSequence.runPresentationPrerequisites { step in
            recorded.append(step)
        }
        #expect(recorded == WorkspaceBootSequence.presentationPrerequisiteSteps)
        #expect(!recorded.contains(.loadCacheStore))
        #expect(!recorded.contains(.loadUIStore))
        #expect(!recorded.contains(.triggerInitialTopologySync))
        #expect(!recorded.contains(.checkWorktrunkDependency))
    }

    @Test("every boot step explains why it exists")
    func bootStepsDocumentTheirPurpose() {
        for step in WorkspaceBootSequence.presentationPrerequisiteSteps
            + WorkspaceBootSequence.postPresentationSteps
        {
            #expect(!step.purpose.isEmpty, "Missing boot purpose for \(step.rawValue)")
        }
    }

    @Test("window presentation precedes independent cache and topology startup")
    func windowPresentationPrecedesIndependentStartupLanes() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate.swift"),
            encoding: .utf8
        )
        let presentation = try #require(
            appDelegateSource.range(of: "self.presentWindowAfterWorkspaceComposition()")
        )
        let postPresentation = try #require(
            appDelegateSource.range(of: "await self.bootWorkspacePostPresentationServices(")
        )

        #expect(presentation.lowerBound < postPresentation.lowerBound)
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
        #expect(appDelegateSource.contains("store.startObserving()"))
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
        #expect(
            appDelegateSource.contains("await workspaceSettingsStore.restoreAsync(for: store.identityAtom.workspaceId)")
        )
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
        #expect(appDelegateSource.contains("workspaceSQLiteDatastore = sqliteDatastore"))
        #expect(appDelegateSource.contains("sqliteDatastore: sqliteDatastore"))
        #expect(appDelegateSource.contains("await store.loadCanonicalComposition()"))
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
        #expect(inboxBootSource.contains("InboxNotificationSQLiteDatastoreAdapter("))
        #expect(inboxBootSource.contains("workspaceId: workspaceId"))
        #expect(inboxBootSource.contains("sqliteAdapter: sqliteAdapter"))
        #expect(!inboxBootSource.contains("workspaceLocalSQLiteStoreBackend"))
        #expect(!inboxBootSource.contains("InboxNotificationSQLiteRepository("))
        #expect(!inboxBootSource.contains("Legacy"))
        #expect(!inboxBootSource.contains("legacy"))
    }

    @Test("pre-boot reopen reports missing main-window dependencies without force-unwrapping them")
    func preBootReopenReportsMainWindowDependencies() throws {
        let delegate = AppDelegate()

        let missingDependencies = delegate.mainWindowCreationMissingDependencyNames()

        #expect(missingDependencies.contains("store"))
        #expect(missingDependencies.contains("executor"))
        #expect(missingDependencies.contains("workspaceSurfaceCoordinator"))
    }

    @Test("reopen window creation uses resolved dependencies")
    func reopenWindowCreationUsesResolvedDependencies() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate.swift"),
            encoding: .utf8
        )
        let mainWindowCreationSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Boot/AppDelegate+MainWindowCreation.swift"
            ),
            encoding: .utf8
        )
        let showWindowFunction = try #require(
            appDelegateSource.range(of: "private func showOrCreateMainWindow()")
        )
        let helperFunction = try #require(
            mainWindowCreationSource.range(of: "func makeMainWindowController")
        )
        let terminationFunction = try #require(
            appDelegateSource.range(of: "func applicationShouldTerminate(_ sender")
        )
        let reopenFunctionBody = String(
            appDelegateSource[showWindowFunction.lowerBound..<terminationFunction.lowerBound]
        )
        let helperFunctionBody = String(mainWindowCreationSource[helperFunction.lowerBound...])

        #expect(reopenFunctionBody.contains("mainWindowCreationDependencies(caller:"))
        #expect(helperFunctionBody.contains("workspaceActionExecutor: dependencies.executor"))
        #expect(helperFunctionBody.contains("scheduleSidebarVisibleWorktreesUpdate()"))
        #expect(!helperFunctionBody.contains("syncFilesystemRootsAndActivity()"))
        #expect(!reopenFunctionBody.contains("workspaceActionExecutor: executor"))
    }

    @Test("canonical boot exhaustively handles strict SQLite load results")
    func canonicalBootExhaustivelyHandlesStrictSQLiteLoadResults() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let workspaceBootSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift"),
            encoding: .utf8
        )
        let workspaceStoreSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift"
            ),
            encoding: .utf8
        )

        #expect(workspaceStoreSource.contains("func loadCanonicalComposition() async -> WorkspaceStoreLoadResult"))
        #expect(workspaceStoreSource.contains("case loaded(WorkspacePreparedCompositionAcceptance)"))
        #expect(
            workspaceStoreSource.contains("case initializedDefaultWorkspace(WorkspacePreparedCompositionAcceptance)"))
        #expect(workspaceStoreSource.contains("case failed(WorkspaceStoreLoadFailure)"))
        #expect(workspaceBootSource.contains("switch await store.loadCanonicalComposition()"))
        #expect(
            workspaceBootSource.contains(
                "case .loaded(let acceptance), .initializedDefaultWorkspace(let acceptance):"
            )
        )
        #expect(
            workspaceBootSource.contains(
                "acceptWorkspacePreparedContentMountCohort(acceptance.contentMountCohort)"
            )
        )
        #expect(workspaceBootSource.contains("case .failed(let failure):"))
        #expect(workspaceBootSource.contains("preconditionFailure(\"Workspace startup invariant violated:"))
        #expect(!workspaceBootSource.contains("restoreFromLegacyJSON"))
        #expect(!workspaceBootSource.contains("saveImportedLegacySnapshot"))
        #expect(!workspaceBootSource.contains("legacyImportStatus"))
        #expect(!workspaceBootSource.contains("WorkspaceLegacyArchiveCoordinator"))
    }

    @Test("authoritative core load installs topology before deferred topology replay")
    func authoritativeCoreLoadInstallsTopologyBeforeDeferredTopologyReplay() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let workspaceBootSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift"),
            encoding: .utf8
        )
        let workspaceStoreSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift"
            ),
            encoding: .utf8
        )
        let canonicalLoad = try #require(
            workspaceBootSource.range(of: "switch await store.loadCanonicalComposition()")
        )
        let deferredTopologyTask = try #require(
            workspaceBootSource.range(of: "initialTopologySyncTask = Task { @MainActor [weak self] in")
        )
        let initialReplay = try #require(
            workspaceBootSource.range(of: "await self.replayBootTopology(")
        )

        #expect(workspaceStoreSource.contains("loadAuthoritativeCoreSnapshot()"))
        #expect(workspaceStoreSource.contains("applyPreparedRepositoryTopology("))
        #expect(canonicalLoad.lowerBound < deferredTopologyTask.lowerBound)
        #expect(deferredTopologyTask.lowerBound < initialReplay.lowerBound)
        #expect(!workspaceBootSource.contains("repositoryTopologyLoadTask"))
    }

    @Test("initial topology trigger starts the persistence observation barrier")
    func initialTopologyTriggerStartsPersistenceObservationBarrier() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let workspaceBootSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift"),
            encoding: .utf8
        )
        let triggerStart = try #require(
            workspaceBootSource.range(of: "private func bootTriggerInitialTopologySync()")
        )
        let deferredLaneStart = try #require(
            workspaceBootSource.range(
                of: "func startDeferredRepositoryTopologyLaneIfRequested()",
                range: triggerStart.upperBound..<workspaceBootSource.endIndex
            )
        )
        let triggerBody = workspaceBootSource[triggerStart.lowerBound..<deferredLaneStart.lowerBound]

        #expect(triggerBody.contains("startDeferredRepositoryTopologyLaneIfRequested()"))
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
