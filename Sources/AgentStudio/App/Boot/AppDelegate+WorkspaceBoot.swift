import AppKit
import Foundation
import Observation

@MainActor
extension AppDelegate {
    func bootWorkspaceServices(
        persistor: WorkspacePersistor,
        paneRuntimeBus: EventBus<RuntimeEnvelope>,
        filesystemSource: inout FilesystemGitPipeline?
    ) async {
        // The boot order is the contract:
        // 1. restore the durable workspace model,
        // 2. load rebuildable caches without autosave observation,
        // 3. stand up runtime event producers/consumers,
        // 4. replay persisted topology through the same coordinator path as live facts,
        // 5. arm cache/UI autosave only after boot mutations have settled.
        //
        // `WorkspaceBootStep.purpose` carries the per-step "why" and is covered by
        // tests so future boot changes cannot silently become an unlabeled ordering bet.
        await WorkspaceBootSequence.runAsync { [self] step in
            recordBootStep(step)
            await executeBootStep(
                step,
                persistor: persistor,
                paneRuntimeBus: paneRuntimeBus,
                filesystemSource: &filesystemSource
            )
        }
    }

    /// Seed pane slots immediately after canonical restore and before any hosting controller exists.
    /// Restored panes already live in `store.paneAtom.panes`; creating their slots here ensures the first
    /// SwiftUI read during tab-host creation sees stable slot identity instead of the lazy fallback.
    func seedSlotsForRestoredPanes() {
        guard store != nil, viewRegistry != nil else { return }
        if store.paneAtom.panes.isEmpty {
            viewRegistry.completeInitialRestore()
        } else {
            viewRegistry.beginInitialRestore()
        }
        for paneId in store.paneAtom.panes.keys {
            viewRegistry.ensureSlot(for: paneId)
        }
        RestoreTrace.log("seedSlotsForRestoredPanes count=\(store.paneAtom.panes.count)")
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
        }
    }

    private func bootLoadCanonicalStore() async {
        atomStore = AtomRegistry()
        atomStore.workspaceRepositoryTopology.setPerformanceTraceRecorder(performanceTraceRecorder)
        AtomScope.setUp(atomStore)
        workspaceSQLiteDatastore = makeWorkspaceSQLiteDatastore(traceRuntime: traceRuntime)
        store = WorkspaceStore(
            identityAtom: atomStore.workspaceIdentity,
            windowMemoryAtom: atomStore.workspaceWindowMemory,
            repositoryTopologyAtom: atomStore.workspaceRepositoryTopology,
            paneAtom: atomStore.workspacePane,
            tabLayoutAtom: atomStore.workspaceTabLayout,
            mutationCoordinator: atomStore.workspaceMutationCoordinator,
            sqliteDatastore: workspaceSQLiteDatastore,
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
            sidebarCheckoutColorAtom: atomStore.sidebarCheckoutColor,
            inboxNotificationPrefsAtom: atomStore.inboxNotificationPrefs,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            }
        )
        paneInboxNotificationPresenter = PaneInboxNotificationPresenter(traceRuntime: traceRuntime)
        Ghostty.ActionRouter.bindTraceRuntime(traceRuntime)
        await store.restoreAsync()
        managementLayerMonitor = ManagementLayerMonitor()
        appLifecycleStore = AppLifecycleAtom()
        windowLifecycleStore = atomStore.windowLifecycle
        applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )
        synchronizeApplicationLifecycleStateAfterWorkspaceBoot(isApplicationActive: NSApp.isActive)
        RestoreTrace.log(
            "store.restore complete tabs=\(store.tabLayoutAtom.tabs.count) panes=\(store.paneAtom.panes.count) activeTab=\(store.tabLayoutAtom.activeTabId?.uuidString ?? "nil")"
        )
    }

    private func makeWorkspaceSQLiteDatastore(traceRuntime: AgentStudioTraceRuntime?) -> WorkspaceSQLiteDatastore? {
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
        await bootArchiveLegacyWorkspaceFilesIfNeeded(persistor: persistor)
    }

    private func bootArchiveLegacyWorkspaceFilesIfNeeded(persistor: WorkspacePersistor) async {
        let archiveResult = await WorkspaceLegacyArchiveCoordinator.archiveLegacyWorkspaceFilesIfReady(
            workspaceId: store.identityAtom.workspaceId,
            persistor: persistor,
            sqliteDatastore: workspaceSQLiteDatastore,
            canArchiveLegacyCompanionFiles: canArchiveLegacyCompanionFiles
        )
        for event in archiveResult.recoveryEvents {
            recordPersistenceRecovery(event)
        }
        let outcome = archiveResult.outcome
        switch outcome {
        case .skipped(.missingSQLiteDatastore), .skipped(.notReady), .skipped(.noLegacyFiles):
            return
        case .skipped(.snapshotStatusUnavailable(let failure)):
            appLogger.warning(
                "Skipping legacy workspace archive; SQLite snapshot status unavailable: \(failure.description)"
            )
        case .skipped(.incompleteCompanionImports):
            appLogger.warning(
                "Skipping legacy workspace archive; one or more legacy companion files have not been restored into SQLite/settings"
            )
        case .skipped(.companionStatusUpdateFailed(let failure)):
            appLogger.warning(
                "Skipping legacy workspace archive; companion import status update failed: \(failure.description)"
            )
        case .archived(let directoryName):
            appLogger.info(
                "Archived legacy workspace files into legacy-imported/\(directoryName, privacy: .public)"
            )
        case .archivedButStatusUpdateFailed(let directoryName, let failure):
            appLogger.warning(
                "Legacy workspace files archived into legacy-imported/\(directoryName, privacy: .public), but archived_at status update failed: \(failure.description)"
            )
        case .archiveIncomplete(let result):
            appLogger.warning(
                "Legacy workspace archive incomplete. Archived: \(result.archivedFilenames.joined(separator: ","), privacy: .public). Failed: \(result.failedFilenames.joined(separator: ","), privacy: .public). Incomplete archive directories: \(result.incompleteArchiveDirectoryNames.joined(separator: ","), privacy: .public)"
            )
        }
    }

    private var canArchiveLegacyCompanionFiles: Bool {
        repoCacheStore.canArchiveLegacyCacheFile
            && sidebarCacheStore.canArchiveLegacySidebarCacheFile
            && uiStateStore.canArchiveLegacyUIFile
            && workspaceSettingsStore.canArchiveLegacySettingsFiles
            && canArchiveLegacyInboxFile
    }

    private func bootEstablishRuntimeBus(
        paneRuntimeBus: EventBus<RuntimeEnvelope>,
        filesystemSource: inout FilesystemGitPipeline?
    ) async {
        runtime = SessionRuntime(atom: atomStore.sessionRuntime, store: store)
        await cleanupOrphanZmxSessions()
        viewRegistry = ViewRegistry()
        closeTransitionCoordinator = PaneCloseTransitionCoordinator()
        seedSlotsForRestoredPanes()
        let pipeline = FilesystemGitPipeline(
            bus: paneRuntimeBus,
            fseventStreamClient: DarwinFSEventStreamClient(),
            performanceTraceRecorder: performanceTraceRecorder
        )
        filesystemSource = pipeline
        watchedFolderCommands = pipeline
        paneCoordinator = PaneCoordinator(
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
            performanceTraceRecorder: performanceTraceRecorder
        )
        workspaceCacheCoordinator = WorkspaceCacheCoordinator(
            bus: paneRuntimeBus,
            workspaceStore: store,
            repoCache: repoCache,
            welcomeAtom: atomStore.welcome,
            topologyEffectHandler: paneCoordinator,
            scopeSyncHandler: { [weak pipeline] change in
                guard let pipeline else { return }
                await pipeline.applyScopeChange(change)
            },
            traceIdentityRefreshHandler: { [weak self] in
                await self?.refreshTraceIdentitySnapshot()
            }
        )
        paneCoordinator.removeRepoHandler = { [weak self] repoId in
            self?.workspaceCacheCoordinator.handleRepoRemoval(repoId: repoId)
            self?.paneCoordinator.syncFilesystemRootsAndActivity()
        }
        executor = ActionExecutor(coordinator: paneCoordinator, store: store)
        tabBarAdapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            performanceTraceRecorder: performanceTraceRecorder
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
        CommandDispatcher.shared.appCommandRouter = self
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
        initialTopologySyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.replayBootTopology(store: self.store, coordinator: self.workspaceCacheCoordinator)
            if let filesystemPipelineBootTask = self.filesystemPipelineBootTask {
                await filesystemPipelineBootTask.value
            }
            self.paneCoordinator.syncFilesystemRootsAndActivity()
            await self.refreshTraceIdentitySnapshot()
            self.observeTraceIdentityInputs()
        }
    }

    func refreshTraceIdentitySnapshot() async {
        let panes = Array(store.paneAtom.panes.values)
        let snapshot = AgentStudioTraceIdentitySnapshot.from(
            repos: store.repositoryTopologyAtom.repos,
            panes: panes,
            worktreeEnrichments: repoCache.worktreeEnrichmentByWorktreeId
        )
        await traceRuntime.updateIdentitySnapshot(snapshot)
    }

    private func observeTraceIdentityInputs() {
        guard !isObservingTraceIdentityInputs else { return }
        isObservingTraceIdentityInputs = true
        withObservationTracking {
            _ = store.paneAtom.panes
            _ = store.repositoryTopologyAtom.repos
            _ = repoCache.worktreeEnrichmentByWorktreeId
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingTraceIdentityInputs = false
                self.observeTraceIdentityInputs()
                await self.refreshTraceIdentitySnapshot()
            }
        }
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
        // Restore and topology replay intentionally run without debounced persistence
        // observation. They can mutate cache atoms many times while runtime cleanup and
        // filesystem discovery are also starting. Arming observation here keeps startup
        // quiet, then immediately persists any stale cache pruning as an explicit boot
        // transaction instead of relying on a debounce side effect.
        repoCacheStore.startObserving()
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
            repoCacheStore.isAutosaveObservationActive,
            "RepoCacheStore autosave observation must be active after \(WorkspaceBootStep.armPersistenceObservation.rawValue)"
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
        for repoId in Array(repoCache.repoEnrichmentByRepoId.keys) where !validRepoIds.contains(repoId) {
            repoCache.removeRepo(repoId)
            didPrune = true
        }
        for worktreeId in Array(repoCache.worktreeEnrichmentByWorktreeId.keys)
        where !validWorktreeIds.contains(worktreeId) {
            repoCache.removeWorktree(worktreeId)
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
                .updateWatchedFolders(paths: watchedPaths.map(\.path))
            )
        }
    }
}

enum WorkspaceLegacyArchiveReadiness {
    static func canArchiveLegacyFiles(
        hasSQLiteBackend: Bool,
        hasCompletedSnapshot: Bool,
        hasLegacyWorkspaceFiles: Bool,
        canArchiveLegacyCompanionFiles: Bool
    ) -> Bool {
        hasSQLiteBackend
            && hasCompletedSnapshot
            && hasLegacyWorkspaceFiles
            && canArchiveLegacyCompanionFiles
    }
}
