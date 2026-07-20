import AppKit
import Foundation
import Observation

@MainActor
extension AppDelegate {
    static func tabNotificationDotColor(
        for lane: InboxNotificationClaimLane?
    ) -> TabNotificationDotColor? {
        switch lane {
        case .actionNeeded:
            return .red
        case .safety:
            return .amber
        case .settledAgent:
            return .yellow
        case .activity, nil:
            return nil
        }
    }

    func bootWorkspacePresentationPrerequisites(
        persistor: WorkspacePersistor,
        paneRuntimeBus: EventBus<RuntimeEnvelope>,
        filesystemSource: inout FilesystemGitPipeline?
    ) async {
        await WorkspaceBootSequence.runPresentationPrerequisitesAsync { [self] step in
            recordBootStep(step)
            await executeBootStep(
                step,
                persistor: persistor,
                paneRuntimeBus: paneRuntimeBus,
                filesystemSource: &filesystemSource
            )
        }
    }

    func bootWorkspacePostPresentationServices(
        persistor: WorkspacePersistor,
        paneRuntimeBus: EventBus<RuntimeEnvelope>,
        filesystemSource: inout FilesystemGitPipeline?
    ) async {
        await WorkspaceBootSequence.runPostPresentationAsync { [self] step in
            recordBootStep(step)
            await executeBootStep(
                step,
                persistor: persistor,
                paneRuntimeBus: paneRuntimeBus,
                filesystemSource: &filesystemSource
            )
        }
        startDeferredRepositoryTopologyLaneIfRequested()
    }

    /// Seed pane slots immediately after canonical composition installation and before any hosting controller exists.
    /// Installed panes already live in `store.paneAtom.panes`; creating their slots here ensures the first
    /// SwiftUI read during tab-host creation sees stable slot identity instead of the lazy fallback.
    func seedSlotsForInstalledPanes() {
        guard store != nil, viewRegistry != nil else { return }
        viewRegistry.beginInitialRestore()
        for paneId in store.paneAtom.panes.keys {
            viewRegistry.ensureSlot(for: paneId)
        }
        RestoreTrace.log("seedSlotsForInstalledPanes count=\(store.paneAtom.panes.count)")
    }

    /// Build a canonical `.repoDiscovered` topology envelope.
    /// Coordinator-originated events use `.builtin(.coordinator)`;
    /// filesystem-originated events use `.builtin(.filesystemWatcher)`.
    static func makeTopologyEnvelope(repoPath: URL, source: SystemSource) -> RuntimeEnvelope {
        nextTopologySeq += 1
        return .system(
            SystemEnvelope(
                source: source,
                seq: nextTopologySeq,
                timestamp: .now,
                event: .topology(
                    .repoDiscovered(
                        repoPath: repoPath,
                        parentPath: repoPath.deletingLastPathComponent()
                    ))
            )
        )
    }

    static func makeWorkspaceActivityEnvelope(_ event: WorkspaceActivityEvent) -> RuntimeEnvelope {
        let seq = WorkspaceActivitySequence.next()
        return .system(
            SystemEnvelope(
                source: .builtin(.coordinator),
                seq: seq,
                timestamp: .now,
                event: .workspaceActivity(event)
            )
        )
    }

    private static var nextTopologySeq: UInt64 = 0

    private func recordBootStep(_ step: WorkspaceBootStep) {
        RestoreTrace.log("workspace.boot.step=\(step.rawValue)")
        startupTraceRecorder.recordWorkspaceBootStep(
            rawValue: step.rawValue,
            purpose: step.purpose
        )
    }

    private func executeBootStep(
        _ step: WorkspaceBootStep,
        persistor: WorkspacePersistor,
        paneRuntimeBus: EventBus<RuntimeEnvelope>,
        filesystemSource: inout FilesystemGitPipeline?
    ) async {
        switch step {
        case .loadCanonicalStore:
            await bootLoadCanonicalStore()
        case .loadCacheStore:
            await bootLoadCacheStore(persistor: persistor)
        case .loadUIStore:
            await bootLoadUIStore(persistor: persistor)
        case .establishRuntimeBus:
            await bootEstablishRuntimeBus(paneRuntimeBus: paneRuntimeBus, filesystemSource: &filesystemSource)
        case .startFilesystemActor:
            bootChainPipelineStep(filesystemSource) { await $0.startFilesystemActor() }
        case .startGitProjector:
            bootChainPipelineStep(filesystemSource) { await $0.startGitProjector() }
        case .startForgeActor:
            bootChainPipelineStep(filesystemSource) { await $0.startForgeActor() }
        case .startCacheCoordinator:
            workspaceCacheCoordinator.startConsuming()
        case .triggerInitialTopologySync:
            bootTriggerInitialTopologySync()
        case .armPersistenceObservation:
            bootArmPersistenceObservation()
        case .readyForReactiveSidebar:
            break
        case .checkWorktrunkDependency:
            presentWorktrunkInstallationOfferIfNeeded()
        }
    }

    private func bootLoadCanonicalStore() async {
        atomStore = AtomRegistry()
        AtomPerformanceTelemetry.shared.configure(traceRuntime: traceRuntime)
        AtomScope.setUp(atomStore)
        let sqliteDatastore = makeWorkspaceSQLiteDatastore(traceRuntime: traceRuntime)
        workspaceSQLiteDatastore = sqliteDatastore
        let workspaceSQLiteSaveCoordinator = WorkspaceSQLiteSaveCoordinator(
            identityAtom: atomStore.workspaceIdentity,
            windowMemoryAtom: atomStore.workspaceWindowMemory,
            repositoryTopologyAtom: atomStore.workspaceRepositoryTopology,
            workspacePaneAtom: atomStore.workspacePane,
            workspaceTabLayoutAtom: atomStore.workspaceTabLayout,
            sqliteDatastore: sqliteDatastore
        )
        let topologyStore = RepositoryTopologyStore(
            atom: atomStore.workspaceRepositoryTopology,
            sqliteDatastore: sqliteDatastore,
            saveCoordinator: workspaceSQLiteSaveCoordinator,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            }
        )
        repositoryTopologyStore = topologyStore
        store = WorkspaceStore(
            identityAtom: atomStore.workspaceIdentity,
            windowMemoryAtom: atomStore.workspaceWindowMemory,
            repositoryTopologyAtom: atomStore.workspaceRepositoryTopology,
            paneAtom: atomStore.workspacePane,
            tabLayoutAtom: atomStore.workspaceTabLayout,
            mutationCoordinator: atomStore.workspaceMutationCoordinator,
            sqliteDatastore: sqliteDatastore,
            sqliteSaveCoordinator: workspaceSQLiteSaveCoordinator,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            }
        )
        repoCacheStore = RepoCacheStore(
            cacheAtom: atomStore.repoEnrichmentCache,
            recentTargetAtom: atomStore.recentWorkspaceTarget,
            sqliteDatastore: workspaceSQLiteDatastore,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            }
        )
        sidebarCacheStore = SidebarCacheStore(
            atom: atomStore.sidebarCache,
            sqliteDatastore: workspaceSQLiteDatastore,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            }
        )
        uiStateStore = UIStateStore(
            atom: atomStore.workspaceSidebarState,
            editorChooserState: atomStore.editorChooser,
            sqliteDatastore: workspaceSQLiteDatastore,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            }
        )
        workspaceSettingsStore = WorkspaceSettingsStore(
            editorPreferenceAtom: atomStore.editorPreference,
            repoExplorerSidebarPrefsAtom: atomStore.repoExplorerSidebarPrefs,
            inboxNotificationPrefsAtom: atomStore.inboxNotificationPrefs,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            }
        )
        paneInboxNotificationPresenter = PaneInboxNotificationPresenter(traceRuntime: traceRuntime)
        Ghostty.ActionRouter.bindTraceRuntime(traceRuntime)
        switch await store.loadCanonicalComposition() {
        case .loaded(let acceptance), .initializedDefaultWorkspace(let acceptance):
            acceptWorkspacePreparedContentMountCohort(acceptance.contentMountCohort)
        case .failed(let failure):
            let diagnosticCode = failure.diagnosticCode
            startupTraceRecorder.recordAppStartup(
                "workspace.startup.invariant_failure",
                phase: "workspace_composition",
                outcome: "failed",
                attributes: [
                    "agentstudio.workspace.startup.failure_code": .string(diagnosticCode.rawValue)
                ]
            )
            preconditionFailure("Workspace startup invariant violated: \(diagnosticCode.rawValue)")
        }
        managementLayerMonitor = ManagementLayerMonitor()
        appLifecycleStore = AppLifecycleAtom()
        windowLifecycleStore = atomStore.windowLifecycle
        applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )
        synchronizeApplicationLifecycleStateAfterWorkspaceBoot(isApplicationActive: NSApp.isActive)
        RestoreTrace.log(
            "workspace.composition.load complete tabs=\(store.tabLayoutAtom.tabs.count) panes=\(store.paneAtom.panes.count) activeTab=\(store.tabLayoutAtom.activeTabId?.uuidString ?? "nil")"
        )
    }

    private func makeWorkspaceSQLiteDatastore(traceRuntime: AgentStudioTraceRuntime?) -> WorkspaceSQLiteDatastore {
        WorkspaceSQLiteDatastoreFactory(traceRuntime: traceRuntime).makeDatastore()
    }

    private func bootLoadCacheStore(persistor: WorkspacePersistor) async {
        _ = persistor
        await repoCacheStore.restoreAsync(for: store.identityAtom.workspaceId)
        await refreshTraceIdentitySnapshot()
        await sidebarCacheStore.restoreAsync(for: store.identityAtom.workspaceId)
    }

    private func bootLoadUIStore(persistor: WorkspacePersistor) async {
        workspaceSettingsStore.restore(for: store.identityAtom.workspaceId)
        await uiStateStore.restoreAsync(for: store.identityAtom.workspaceId)
        await bootLoadInboxNotificationStore(persistor: persistor)
    }

    private func bootEstablishRuntimeBus(
        paneRuntimeBus: EventBus<RuntimeEnvelope>,
        filesystemSource: inout FilesystemGitPipeline?
    ) async {
        runtime = SessionRuntime(atom: atomStore.sessionRuntime, store: store)
        viewRegistry = ViewRegistry()
        closeTransitionCoordinator = PaneCloseTransitionCoordinator()
        seedSlotsForInstalledPanes()
        let pipeline = FilesystemGitPipeline(
            bus: paneRuntimeBus,
            fseventStreamClient: DarwinFSEventStreamClient(),
            performanceTraceRecorder: performanceTraceRecorder
        )
        filesystemSource = pipeline
        watchedFolderCommands = pipeline
        SurfaceManager.shared.setPerformanceTraceRecorder(performanceTraceRecorder)
        workspaceSurfaceCoordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: SurfaceManager.shared,
            startupTraceRecorder: startupTraceRecorder,
            runtimeRegistry: .shared,
            paneEventBus: paneRuntimeBus,
            closeTransitionCoordinator: closeTransitionCoordinator,
            filesystemSource: pipeline,
            windowLifecycleStore: windowLifecycleStore,
            traceRuntime: traceRuntime,
            performanceTraceRecorder: performanceTraceRecorder,
            traceIdentityRefreshHandler: { [weak self] in
                self?.requestTraceIdentityRefresh()
            }
        )
        let contentMountCohort = acceptedWorkspacePreparedContentMountCohort
        let terminalAdmissionPort = PreparedTerminalMountAdmissionPort(
            generation: contentMountCohort.generation,
            viewRegistry: viewRegistry,
            mountHandler: workspaceSurfaceCoordinator
        )
        let contentMountCoordinator = WorkspacePreparedContentMountCoordinator(
            cohort: contentMountCohort,
            viewRegistry: viewRegistry,
            terminalAdmissionPort: terminalAdmissionPort,
            nonterminalAdmissionPort: PreparedNonterminalMountAdmissionPort(
                generation: contentMountCohort.generation,
                coordinator: workspaceSurfaceCoordinator
            )
        )
        installWorkspacePreparedContentMountOwners(
            InstalledWorkspacePreparedContentMountOwners(
                cohort: contentMountCohort,
                terminalAdmissionPort: terminalAdmissionPort,
                coordinator: contentMountCoordinator
            )
        )
        workspaceSurfaceCoordinator.preparedContentVisibilitySignalHandler = { [weak contentMountCoordinator] paneIDs in
            contentMountCoordinator?.handleVisibilitySignals(for: paneIDs) ?? []
        }
        workspaceCacheCoordinator = WorkspaceCacheCoordinator(
            bus: paneRuntimeBus,
            workspaceStore: store,
            repoCache: repoCache,
            welcomeAtom: atomStore.welcome,
            topologyEffectHandler: workspaceSurfaceCoordinator,
            scopeSyncHandler: { [weak pipeline] change in
                guard let pipeline else { return }
                await pipeline.applyScopeChange(change)
            },
            traceIdentityRefreshHandler: { [weak self] in
                self?.requestTraceIdentityRefresh()
            }
        )
        workspaceSurfaceCoordinator.removeRepoHandler = { [weak self] repoId in
            self?.workspaceCacheCoordinator.handleRepoRemoval(repoId: repoId)
            self?.workspaceSurfaceCoordinator.syncFilesystemRootsAndActivity()
        }
        executor = WorkspaceActionExecutor(coordinator: workspaceSurfaceCoordinator, store: store)
        tabBarAdapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            performanceTraceRecorder: performanceTraceRecorder,
            notificationDotColorProvider: { paneIds in
                Self.tabNotificationDotColor(
                    for: atom(\.inboxNotification).attentionLane(forPaneIds: paneIds)
                )
            },
            observeNotificationDotInputs: {
                _ = atom(\.inboxNotification).notifications
            }
        )
        commandBarController = CommandBarPanelController(
            store: store,
            repoCache: repoCache,
            dispatcher: .shared,
            notificationInboxCommands: makeInboxNotificationCommands(),
            commandBarSurface: atomStore.commandBarSurface,
            performanceTraceRecorder: performanceTraceRecorder
        )
        bootStartInboxNotificationRouter(bus: paneRuntimeBus)
        bootStartTerminalActivityRouter(bus: paneRuntimeBus)
        AppCommandDispatcher.shared.appCommandRouter = self
        oauthService = OAuthService()
    }

    private func bootChainPipelineStep(
        _ filesystemSource: FilesystemGitPipeline?,
        action: @escaping @Sendable (FilesystemGitPipeline) async -> Void
    ) {
        guard let filesystemSource else { return }
        let previousTask = filesystemPipelineBootTask
        filesystemPipelineBootTask = Task {
            if let previousTask {
                await previousTask.value
            }
            await action(filesystemSource)
        }
    }

    private func bootTriggerInitialTopologySync() {
        shouldStartRepositoryTopologyAfterWindowPresentation = true
        startDeferredRepositoryTopologyLaneIfRequested()
    }

    func startDeferredRepositoryTopologyLaneIfRequested() {
        guard shouldStartRepositoryTopologyAfterWindowPresentation else { return }
        shouldStartRepositoryTopologyAfterWindowPresentation = false
        let loadedWorkspaceID = store.identityAtom.workspaceId
        let topologyStore = repositoryTopologyStore!
        let repositoryTopologyLoadTask = Task { @MainActor in
            await topologyStore.restoreAsync(for: loadedWorkspaceID)
        }
        self.repositoryTopologyLoadTask = repositoryTopologyLoadTask
        initialTopologySyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await repositoryTopologyLoadTask.value
            await self.replayBootTopology(store: self.store, coordinator: self.workspaceCacheCoordinator)
            if let filesystemPipelineBootTask = self.filesystemPipelineBootTask {
                await filesystemPipelineBootTask.value
            }
            self.workspaceSurfaceCoordinator.syncFilesystemRootsAndActivity()
            self.requestTraceIdentityRefresh()
            await self.waitForTraceIdentityRefreshIdle()
        }
    }

    func requestTraceIdentityRefresh() {
        let isCoalesced = traceIdentityRefreshTask != nil
        performanceTraceRecorder.recordTraceIdentitySnapshot(
            TraceIdentityPerformanceSnapshot(
                refreshRequestCount: 1,
                coalescedRequestCount: isCoalesced ? 1 : 0,
                fleetCaptureCount: 0,
                equalSnapshotSuppressedCount: 0
            )
        )
        if isCoalesced {
            if isTraceIdentityCaptureInProgress {
                traceIdentityRefreshNeedsReplay = true
            }
            return
        }

        traceIdentityRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.isTraceIdentityCaptureInProgress = true
                await self.refreshTraceIdentitySnapshot()
                self.isTraceIdentityCaptureInProgress = false
                guard self.traceIdentityRefreshNeedsReplay else {
                    self.traceIdentityRefreshTask = nil
                    return
                }
                self.traceIdentityRefreshNeedsReplay = false
            }
            self.traceIdentityRefreshTask = nil
        }
    }

    func waitForTraceIdentityRefreshIdle() async {
        while let activeTask = traceIdentityRefreshTask {
            await activeTask.value
        }
    }

    func refreshTraceIdentitySnapshot() async {
        let panes = Array(store.paneAtom.panes.values)
        let snapshot = AgentStudioTraceIdentitySnapshot.from(
            repos: store.repositoryTopologyAtom.repos,
            panes: panes,
            worktreeEnrichments: repoCache.worktreeEnrichmentSnapshot()
        )
        let updateOutcome = await traceRuntime.updateIdentitySnapshot(snapshot)
        traceIdentityFleetCaptureCount &+= 1
        performanceTraceRecorder.recordTraceIdentitySnapshot(
            TraceIdentityPerformanceSnapshot(
                refreshRequestCount: 0,
                coalescedRequestCount: 0,
                fleetCaptureCount: 1,
                equalSnapshotSuppressedCount: updateOutcome == .equalSuppressed ? 1 : 0
            )
        )
    }

    private func bootArmPersistenceObservation() {
        let topologySyncTask = initialTopologySyncTask
        persistenceObservationBootTask = Task { @MainActor [weak self] in
            if let topologySyncTask {
                await topologySyncTask.value
            }
            await self?.completeBootPersistenceObservation()
        }
    }

    private func completeBootPersistenceObservation() async {
        // Composition loading and topology replay intentionally run without debounced persistence
        // observation. They can mutate cache atoms many times while runtime cleanup and
        // filesystem discovery are also starting. Arming observation here keeps startup
        // quiet, then immediately persists any stale cache pruning as an explicit boot
        // transaction instead of relying on a debounce side effect.
        store.startObserving()
        repoCacheStore.startObserving()
        repositoryTopologyStore.startObserving()
        sidebarCacheStore.startObserving()
        uiStateStore.startObserving()
        workspaceSettingsStore.startObserving()
        assertBootPersistenceObservationArmed()

        if pruneStaleCache(store: store, repoCache: repoCache) {
            do {
                try await repoCacheStore.flushAsync(for: store.identityAtom.workspaceId)
            } catch {
                appLogger.warning("Failed to persist pruned repo cache during boot: \(error.localizedDescription)")
            }
        }
    }

    private func assertBootPersistenceObservationArmed() {
        assert(
            store.isAutosaveObservationActive,
            "WorkspaceStore autosave observation must be active after \(WorkspaceBootStep.armPersistenceObservation.rawValue)"
        )
        assert(
            repoCacheStore.isAutosaveObservationActive,
            "RepoCacheStore autosave observation must be active after \(WorkspaceBootStep.armPersistenceObservation.rawValue)"
        )
        assert(
            repositoryTopologyStore.isAutosaveObservationActive,
            "RepositoryTopologyStore autosave observation must be active after \(WorkspaceBootStep.armPersistenceObservation.rawValue)"
        )
        assert(
            sidebarCacheStore.isAutosaveObservationActive,
            "SidebarCacheStore autosave observation must be active after \(WorkspaceBootStep.armPersistenceObservation.rawValue)"
        )
        assert(
            uiStateStore.isAutosaveObservationActive,
            "UIStateStore autosave observation must be active after \(WorkspaceBootStep.armPersistenceObservation.rawValue)"
        )
        assert(
            workspaceSettingsStore.isAutosaveObservationActive,
            "WorkspaceSettingsStore autosave observation must be active after \(WorkspaceBootStep.armPersistenceObservation.rawValue)"
        )
    }

    private func pruneStaleCache(store: WorkspaceStore, repoCache: RepoCacheAtom) -> Bool {
        let repos = store.repositoryTopologyAtom.repos
        let validRepoIds = Set(repos.map(\.id))
        let validWorktreeIds = Set(repos.flatMap(\.worktrees).map(\.id))
        var didPrune = false
        for repoId in Array(repoCache.repoEnrichmentSnapshot().keys) where !validRepoIds.contains(repoId) {
            repoCache.removeRepo(repoId)
            didPrune = true
        }
        for worktreeId in Array(repoCache.worktreeEnrichmentSnapshot().keys)
        where !validWorktreeIds.contains(worktreeId) {
            repoCache.removeWorktree(worktreeId)
            didPrune = true
        }
        if repoCache.enrichmentCacheAtom.pruneNilSlots(
            validRepoIds: validRepoIds,
            validWorktreeIds: validWorktreeIds
        ) {
            didPrune = true
        }
        return didPrune
    }

    private func replayBootTopology(store: WorkspaceStore, coordinator: WorkspaceCacheCoordinator) async {
        let tabLayout = store.tabLayoutAtom
        let workspacePane = store.paneAtom
        let repos = store.repositoryTopologyAtom.repos
        let watchedPaths = store.repositoryTopologyAtom.watchedPaths
        let activePaneRepoIds: Set<UUID> = {
            guard let activeTab = tabLayout.activeTab else { return [] }
            let repoIds = activeTab.activePaneIds.compactMap { workspacePane.panes[$0]?.repoId }
            return Set(repoIds)
        }()
        let prioritizedRepos = repos.sorted { a, b in
            let aActive = activePaneRepoIds.contains(a.id)
            let bActive = activePaneRepoIds.contains(b.id)
            if aActive != bActive { return aActive }
            return false
        }
        let bus = PaneRuntimeEventBus.shared
        for repo in prioritizedRepos {
            await bus.post(
                Self.makeTopologyEnvelope(
                    repoPath: repo.repoPath,
                    source: .builtin(.coordinator)
                )
            )
        }

        if !watchedPaths.isEmpty {
            await coordinator.syncScope(
                .updateWatchedFolders(watchedPaths: watchedPaths)
            )
        }
    }
}
