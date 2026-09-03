import AgentStudioBridge
import AgentStudioCommandBar
import AgentStudioCore
import AgentStudioInboxNotification
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import AgentStudioTerminal
import AppKit
import Foundation
import Observation

@MainActor
extension AppDelegate {
    func bootWorkspacePresentationPrerequisites(
        paneRuntimeBus: EventBus<RuntimeEnvelope>,
        filesystemSource: inout FilesystemGitPipeline?
    ) async {
        await WorkspaceBootSequence.runPresentationPrerequisitesAsync { [self] step in
            recordBootStep(step)
            await executeBootStep(
                step,
                paneRuntimeBus: paneRuntimeBus,
                filesystemSource: &filesystemSource
            )
        }
    }

    func bootWorkspacePostPresentationServices(
        paneRuntimeBus: EventBus<RuntimeEnvelope>,
        filesystemSource: inout FilesystemGitPipeline?
    ) async {
        await WorkspaceBootSequence.runPostPresentationAsync { [self] step in
            recordBootStep(step)
            await executeBootStep(
                step,
                paneRuntimeBus: paneRuntimeBus,
                filesystemSource: &filesystemSource
            )
        }
        startDeferredRepositoryTopologyLaneIfRequested()
    }

    /// Seed pane slots immediately after canonical composition installation and before any hosting controller exists.
    /// Installed pane identities already live in `store.paneAtom.graphAtom`; creating their slots here ensures the first
    /// SwiftUI read during tab-host creation sees stable slot identity instead of the lazy fallback.
    func seedSlotsForInstalledPanes() {
        guard store != nil, viewRegistry != nil else { return }
        viewRegistry.beginInitialRestore()
        for paneId in store.paneAtom.graphAtom.paneIDs {
            viewRegistry.ensureSlot(for: paneId)
        }
        RestoreTrace.log("seedSlotsForInstalledPanes count=\(store.paneAtom.graphAtom.paneIDs.count)")
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
        paneRuntimeBus: EventBus<RuntimeEnvelope>,
        filesystemSource: inout FilesystemGitPipeline?
    ) async {
        switch step {
        case .prepareDatabases:
            await bootPrepareDatabases()
        case .loadCanonicalStore:
            await bootLoadCanonicalStore()
        case .loadCacheStore:
            await bootLoadCacheStore()
        case .loadUIStore:
            await bootLoadUIStore()
        case .establishRuntimeBus:
            await bootEstablishRuntimeBus(paneRuntimeBus: paneRuntimeBus, filesystemSource: &filesystemSource)
        case .startFilesystemActor:
            bootChainPipelineStep(filesystemSource) { await $0.startFilesystemActor() }
        case .startGitProjector:
            bootChainPipelineStep(filesystemSource) { await $0.startGitProjector() }
        case .startForgeActor:
            bootChainPipelineStep(filesystemSource) { await $0.startForgeActor() }
        case .startCacheCoordinator:
            await workspaceCacheCoordinator.startConsuming()
        case .triggerInitialTopologySync:
            bootTriggerInitialTopologySync()
        case .armPersistenceObservation:
            bootArmPersistenceObservation()
        case .readyForReactiveSidebar:
            break
        }
    }

    private func bootPrepareDatabases() async {
        let sqliteDatastore = makeWorkspaceSQLiteDatastore(traceRuntime: traceRuntime)
        workspaceSQLiteDatastore = sqliteDatastore
        switch await sqliteDatastore.prepareDatabasesForBoot() {
        case .prepared:
            break
        case .failed(let failure):
            let diagnosticCode: WorkspaceStartupFailureDiagnosticCode
            switch failure.kind {
            case .sqliteUnavailable:
                diagnosticCode = .sqliteUnavailable
            case .compositionRejected:
                diagnosticCode = .compositionRejected
            case .topologyRejected:
                await recordPaneTopologyPersistenceReason(
                    .topologyNormalizationRejected,
                    severity: .error
                )
                diagnosticCode = .topologyRejected
            }
            try? await traceRuntime.flush()
            preconditionFailure(
                "Workspace startup invariant violated: "
                    + diagnosticCode.rawValue
            )
        }
    }

    private func bootLoadCanonicalStore() async {
        atomStore = AtomRegistry()
        configurePerformanceTelemetry()
        CoreAtomScope.setUp(atomStore.core)
        atomStore.core.workspaceRepositoryTopology.setWorktreePathAmbiguityReporter { [weak self] in
            Task { @MainActor [weak self] in
                await self?.recordPaneTopologyPersistenceReason(.paneTopologyAssociationAmbiguous)
            }
        }
        guard let sqliteDatastore = workspaceSQLiteDatastore else {
            preconditionFailure("Workspace databases were not prepared before canonical hydration")
        }
        let workspaceSQLiteSaveCoordinator = WorkspaceSQLiteSaveCoordinator(
            identityAtom: atomStore.core.workspaceIdentity,
            windowMemoryAtom: atomStore.core.workspaceWindowMemory,
            workspacePaneAtom: atomStore.core.workspacePane,
            workspaceTabLayoutAtom: atomStore.core.workspaceTabLayout,
            sqliteDatastore: sqliteDatastore
        )
        let topologyStore = RepositoryTopologyStore(
            atom: atomStore.core.workspaceRepositoryTopology,
            sqliteDatastore: sqliteDatastore
        )
        repositoryTopologyStore = topologyStore
        store = WorkspaceStore(
            identityAtom: atomStore.core.workspaceIdentity,
            windowMemoryAtom: atomStore.core.workspaceWindowMemory,
            repositoryTopologyAtom: atomStore.core.workspaceRepositoryTopology,
            paneAtom: atomStore.core.workspacePane,
            tabLayoutAtom: atomStore.core.workspaceTabLayout,
            mutationCoordinator: atomStore.core.workspaceMutationCoordinator,
            sqliteDatastore: sqliteDatastore,
            sqliteSaveCoordinator: workspaceSQLiteSaveCoordinator,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            },
            paneAssociationBootReconciliationReporter: { [weak self] summary in
                self?.performanceTraceRecorder.recordPaneAssociationBootReconciliation(summary)
            },
            persistenceReasonReporter: { [weak self] reason in
                Task { @MainActor [weak self] in
                    await self?.recordPaneTopologyPersistenceReason(reason)
                }
            }
        )
        repoCacheStore = RepoCacheStore(
            cacheAtom: atomStore.core.repoEnrichmentCache,
            sqliteDatastore: sqliteDatastore,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            }
        )
        entityRecencyStore = EntityRecencyStore(
            applicationAtom: atomStore.core.applicationEntityRecency,
            workspaceAtom: atomStore.core.workspaceEntityRecency,
            sqliteDatastore: sqliteDatastore
        )
        repositoryLocalActivityStore = makeRepositoryLocalActivityStore(sqliteDatastore: sqliteDatastore)
        sidebarCacheStore = SidebarCacheStore(
            atom: atomStore.core.sidebarCache,
            sqliteDatastore: sqliteDatastore,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            }
        )
        uiStateStore = UIStateStore(
            atom: atomStore.core.workspaceSidebarState,
            sqliteDatastore: sqliteDatastore,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            }
        )
        workspaceSettingsStore = makeWorkspaceSettingsStore(sqliteDatastore: sqliteDatastore)
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
        configureInteractionPerformanceProbeOwners()
        appLifecycleStore = AppLifecycleAtom()
        windowLifecycleStore = atomStore.core.windowLifecycle
        applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore,
            performanceTraceRecorder: performanceTraceRecorder
        )
        synchronizeApplicationLifecycleStateAfterWorkspaceBoot(isApplicationActive: NSApp.isActive)
        RestoreTrace.log(
            "workspace.composition.load complete tabs=\(store.tabLayoutAtom.tabs.count) panes=\(store.paneAtom.graphAtom.paneIDs.count) activeTab=\(store.tabLayoutAtom.activeTabId?.uuidString ?? "nil")"
        )
    }

    private func configurePerformanceTelemetry() {
        AtomPerformanceTelemetry.shared.configure(traceRuntime: traceRuntime)
        RepoExplorerPerformanceTelemetry.shared.configure(
            traceRuntime: traceRuntime,
            performanceTraceRecorder: performanceTraceRecorder
        )
    }

    private func configureInteractionPerformanceProbeOwners() {
        let interactionProbe = AgentStudioInteractionPerformanceProbe(recorder: performanceTraceRecorder)
        managementLayerMonitor = ManagementLayerMonitor(interactionProbe: interactionProbe)
        AppCommandDispatcher.shared.interactionProbe = interactionProbe
        AppCommandDispatcher.shared.onCommandRefreshAccepted = { [weak managementLayerMonitor] correlationId in
            managementLayerMonitor?.prepareCommandRefreshSettlement(correlationId: correlationId)
        }
    }

    private func makeWorkspaceSQLiteDatastore(traceRuntime: AgentStudioTraceRuntime?) -> WorkspaceSQLiteDatastore {
        WorkspaceSQLiteDatastoreFactory(traceRuntime: traceRuntime).makeDatastore()
    }

    func makeWorkspaceSettingsStore(
        sqliteDatastore: WorkspaceSQLiteDatastore
    ) -> WorkspaceSettingsStore {
        WorkspaceSettingsStore(
            editorPreferenceAtom: atomStore.editorPreference,
            repoExplorerSidebarPrefsAtom: atomStore.repoExplorerSidebarPrefs,
            sqliteDatastore: sqliteDatastore,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            }
        )
    }

    private func bootLoadCacheStore() async {
        await entityRecencyStore.restoreApplicationAsync()
        await entityRecencyStore.restoreWorkspaceAsync(for: store.identityAtom.workspaceId)
        await repositoryLocalActivityStore.restoreAsync()
        await repoCacheStore.restoreAsync(for: store.identityAtom.workspaceId)
        await refreshTraceIdentitySnapshot()
        await sidebarCacheStore.restoreAsync(for: store.identityAtom.workspaceId)
    }

    private func bootLoadUIStore() async {
        await workspaceSettingsStore.restoreAsync(for: store.identityAtom.workspaceId)
        await uiStateStore.restoreAsync(for: store.identityAtom.workspaceId)
    }

    private func bootEstablishRuntimeBus(
        paneRuntimeBus: EventBus<RuntimeEnvelope>,
        filesystemSource: inout FilesystemGitPipeline?
    ) async {
        runtime = SessionRuntime(atom: atomStore.core.sessionRuntime, store: store)
        viewRegistry = ViewRegistry()
        closeTransitionCoordinator = PaneCloseTransitionCoordinator()
        bridgeGitReadScheduler = BridgeGitReadScheduler(
            topology: .recoveryBaseline,
            eventSink: BridgeNativeCapacityTraceRecorder.schedulerEventSink(
                performanceTraceRecorder: performanceTraceRecorder
            )
        )
        bridgeWorktreeProductConstructionCoordinator =
            BridgeWorktreeProductConstructionCoordinator(
                eventSink: BridgeNativeCapacityTraceRecorder.constructionEventSink(
                    performanceTraceRecorder: performanceTraceRecorder
                )
            )
        seedSlotsForInstalledPanes()
        let gitStatusPhysicalGate = AgentStudioGitStatusPhysicalGate()
        let fseventStreamClient = DarwinFSEventStreamClient()
        bootRegisterFilesystemIngressPerformanceReporter(for: fseventStreamClient)
        let repositoryLocalActivityProjector = makeRepositoryLocalActivityProjector()
        let gitWorkingTreeStatusProvider = AgentStudioGitWorkingTreeStatusProvider(
            physicalGate: gitStatusPhysicalGate,
            continuityWitness: fseventStreamClient
        )
        let pipeline = FilesystemGitPipeline(
            bus: paneRuntimeBus,
            gitWorkingTreeProvider: gitWorkingTreeStatusProvider,
            fseventStreamClient: fseventStreamClient,
            repositoryLocalActivityProjector: repositoryLocalActivityProjector,
            performanceTraceRecorder: performanceTraceRecorder
        )
        filesystemSource = pipeline
        watchedFolderCommands = pipeline
        repositoryFactUpdateSource = pipeline
        SurfaceManager.shared.setPerformanceTraceRecorder(performanceTraceRecorder)
        SurfaceManager.shared.setAppCommandDispatcher(AppCommandDispatcher.shared)
        workspaceSurfaceCoordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: SurfaceManager.shared,
            startupTraceRecorder: startupTraceRecorder,
            runtimeRegistry: .shared,
            paneEventBus: paneRuntimeBus,
            closeTransitionCoordinator: closeTransitionCoordinator,
            bridgeGitReadScheduler: bridgeGitReadScheduler,
            worktreeProductConstructionCoordinator: bridgeWorktreeProductConstructionCoordinator,
            gitWorkingTreeStatusProvider: gitWorkingTreeStatusProvider,
            gitStatusPhysicalGate: gitStatusPhysicalGate,
            filesystemSource: pipeline,
            windowLifecycleStore: windowLifecycleStore,
            appLifecycleStore: appLifecycleStore,
            bridgePaneAttendance: atomStore.bridgePaneAttendance,
            traceRuntime: traceRuntime,
            performanceTraceRecorder: performanceTraceRecorder,
            traceIdentityRefreshHandler: { [weak self] in
                self?.requestTraceIdentityRefresh()
            }
        )
        bootInstallPreparedContentMountOwners(coordinator: workspaceSurfaceCoordinator)
        workspaceCacheCoordinator = WorkspaceCacheCoordinator(
            bus: paneRuntimeBus,
            workspaceStore: store,
            repoCache: repoCache,
            welcomeAtom: atomStore.core.welcome,
            topologyEffectHandler: workspaceSurfaceCoordinator,
            scopeSyncHandler: { [weak pipeline] change in
                guard let pipeline else { return }
                await pipeline.applyScopeChange(change)
            },
            traceIdentityRefreshHandler: { [weak self] in
                self?.requestTraceIdentityRefresh()
            },
            performanceTraceRecorder: performanceTraceRecorder
        )
        workspaceSurfaceCoordinator.removeRepoHandler = { [weak self] repoId in
            self?.cancelRepositoryFactUpdate(repoId: repoId)
            self?.workspaceCacheCoordinator.handleRepoRemoval(repoId: repoId)
            self?.workspaceSurfaceCoordinator.syncFilesystemRootsAndActivity()
        }
        executor = WorkspaceActionExecutor(coordinator: workspaceSurfaceCoordinator, store: store)
        startWorkspacePaneRecencyObservation()
        commandBarController = CommandBarPanelController(
            store: store,
            octiconLoader: octiconLoader,
            repoCache: repoCache,
            dispatcher: AppCommandDispatcher.shared,
            quickOpenDirectoryHandler: { directory, placement in
                AppCommandDispatcher.shared.dispatchQuickOpenDirectory(
                    directory,
                    placement: placement
                )
            },
            commandBarSurface: atomStore.core.commandBarSurface,
            performanceTraceRecorder: performanceTraceRecorder
        )
        bootStartTerminalActivityRouter(bus: paneRuntimeBus)
        AppCommandDispatcher.shared.appCommandRouter = self
        oauthService = OAuthService()
    }

    private func makeRepositoryLocalActivityStore(
        sqliteDatastore: WorkspaceSQLiteDatastore
    ) -> RepositoryLocalActivityStore {
        RepositoryLocalActivityStore(
            atom: atomStore.core.repositoryLocalActivity,
            sqliteDatastore: sqliteDatastore
        )
    }

    private func makeRepositoryLocalActivityProjector() -> RepositoryLocalActivityProjector {
        let localActivityStore = repositoryLocalActivityStore!
        return RepositoryLocalActivityProjector(
            authorityRevocationSink: { repositoryStableKeys in
                await localActivityStore.revokeCurrentSessionAuthority(
                    for: repositoryStableKeys
                )
            },
            commitSink: { commit in
                _ = try await localActivityStore.commitAsync(commit)
            }
        )
    }

    private func bootRegisterFilesystemIngressPerformanceReporter(
        for fseventStreamClient: DarwinFSEventStreamClient
    ) {
        guard let performanceTraceRecorder else { return }
        let client = fseventStreamClient
        let recorder = performanceTraceRecorder
        performanceTraceRecorder.registerPeriodicSnapshotReporter { [weak client, weak recorder] in
            guard let client, let recorder else { return }
            var attributes = client.snapshotAndResetIngressPerformance().traceAttributes
            let observationSnapshot = client.sharedLocalObservationSnapshot()
            attributes["agentstudio.performance.filesystem.local_stream.physical.count"] = .int(
                observationSnapshot.physicalStreamCount
            )
            attributes["agentstudio.performance.filesystem.local_stream.logical_registration.count"] = .int(
                observationSnapshot.logicalRegistrationCount
            )
            recorder.record(
                .filesystemIngressSnapshot,
                attributes: attributes
            )
        }
    }

    private func bootInstallPreparedContentMountOwners(coordinator: WorkspaceSurfaceCoordinator) {
        let contentMountCohort = acceptedWorkspacePreparedContentMountCohort
        let terminalAdmissionPort = PreparedTerminalMountAdmissionPort(
            generation: contentMountCohort.generation,
            viewRegistry: viewRegistry,
            mountHandler: coordinator
        )
        let contentMountCoordinator = WorkspacePreparedContentMountCoordinator(
            cohort: contentMountCohort,
            viewRegistry: viewRegistry,
            terminalAdmissionPort: terminalAdmissionPort,
            nonterminalAdmissionPort: PreparedNonterminalMountAdmissionPort(
                generation: contentMountCohort.generation,
                coordinator: coordinator
            )
        )
        installWorkspacePreparedContentMountOwners(
            InstalledWorkspacePreparedContentMountOwners(
                cohort: contentMountCohort,
                terminalAdmissionPort: terminalAdmissionPort,
                coordinator: contentMountCoordinator
            )
        )
        coordinator.preparedContentVisibilitySignalHandler = { [weak contentMountCoordinator] paneIDs in
            contentMountCoordinator?.handleVisibilitySignals(for: paneIDs) ?? []
        }
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
        guard shouldStartRepositoryTopologyAfterWindowPresentation,
            didPassInitialTopologyPersistenceBarrier
        else { return }
        shouldStartRepositoryTopologyAfterWindowPresentation = false
        initialTopologySyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.replayBootTopology(store: self.store, coordinator: self.workspaceCacheCoordinator)
            await self.repairUnavailableRepositoriesMissingMain()
            self.workspaceSurfaceCoordinator.repairRestoredBridgePanesAfterInitialTopologyReplay()
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
        let panes = Array(store.paneAtom.paneSnapshot().values)
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
        persistenceObservationBootTask = Task { @MainActor [weak self] in
            await self?.completeBootPersistenceObservation()
        }
    }

    private func completeBootPersistenceObservation() async {
        store.startObserving()
        repositoryTopologyStore.startObserving()

        do {
            try await repositoryTopologyStore.flushAsync()
            didPassInitialTopologyPersistenceBarrier = true
            startDeferredRepositoryTopologyLaneIfRequested()
        } catch {
            didPassInitialTopologyPersistenceBarrier = false
            appLogger.warning("Failed to persist normalized repository topology during boot")
            await recordPaneTopologyPersistenceReason(
                .topologyBootNormalizationFlushFailed,
                severity: .error
            )
        }

        repoCacheStore.startObserving()
        entityRecencyStore.startObserving()
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

    private func repairUnavailableRepositoriesMissingMain() async {
        let candidates = store.repositoryTopologyAtom.repos.filter { repository in
            store.repositoryTopologyAtom.isRepoUnavailable(repository.id)
                && !Self.hasValidMainWorktree(repository)
        }
        for repository in candidates {
            let result = await RepoScanner().scan(in: repository.repoPath, maxDepth: 0)
            let normalizedRepositoryPath = RepoScanner.canonicalURL(repository.repoPath)
            guard let repairedWorktrees = Self.repairedWorktrees(for: repository, from: result) else { continue }

            switch workspaceCacheCoordinator.reassociateRepo(
                repoId: repository.id,
                to: normalizedRepositoryPath,
                discoveredWorktrees: repairedWorktrees
            ) {
            case .accepted:
                await recordPaneTopologyPersistenceReason(.topologyScanMainRepaired)
            case .rejected:
                continue
            }
        }
    }

    static func hasValidMainWorktree(_ repository: Repo) -> Bool {
        let normalizedRepositoryPath = RepoScanner.canonicalURL(repository.repoPath)
        let mainWorktrees = repository.worktrees.filter(\.isMainWorktree)
        return mainWorktrees.count == 1
            && RepoScanner.canonicalURL(mainWorktrees[0].path) == normalizedRepositoryPath
    }

    static func repairedWorktrees(
        for repository: Repo,
        from result: RepoScannerResult
    ) -> [Worktree]? {
        guard case .completeAuthoritative(let completeScan) = result else { return nil }
        let normalizedRepositoryPath = RepoScanner.canonicalURL(repository.repoPath)
        guard
            completeScan.verifiedEntries.contains(where: { entry in
                guard case .cloneRoot = entry.kind else { return false }
                return RepoScanner.canonicalURL(entry.path) == normalizedRepositoryPath
            })
        else {
            return nil
        }

        var repairedWorktrees = repository.worktrees.map { worktree in
            var repairedWorktree = worktree
            repairedWorktree.isMainWorktree = false
            return repairedWorktree
        }
        if let rootIndex = repairedWorktrees.firstIndex(where: {
            RepoScanner.canonicalURL($0.path) == normalizedRepositoryPath
        }) {
            repairedWorktrees[rootIndex].name = normalizedRepositoryPath.lastPathComponent
            repairedWorktrees[rootIndex].path = normalizedRepositoryPath
            repairedWorktrees[rootIndex].isMainWorktree = true
        } else {
            repairedWorktrees.append(
                Worktree(
                    id: UUIDv7.generate(),
                    repoId: repository.id,
                    name: normalizedRepositoryPath.lastPathComponent,
                    path: normalizedRepositoryPath,
                    isMainWorktree: true
                )
            )
        }
        return repairedWorktrees
    }

    private func recordPaneTopologyPersistenceReason(
        _ reason: PaneTopologyPersistenceReason,
        severity: AgentStudioTraceSeverity = .info
    ) async {
        await traceRuntime.record(
            tag: .persistenceOperation,
            body: reason.rawValue,
            severity: severity,
            attributes: ["agentstudio.persistence.reason": .string(reason.rawValue)]
        )
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
            entityRecencyStore.isApplicationObservationActive
                && entityRecencyStore.isWorkspaceObservationActive,
            "EntityRecencyStore observations must be active after \(WorkspaceBootStep.armPersistenceObservation.rawValue)"
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
        return didPrune
    }

    private func replayBootTopology(store: WorkspaceStore, coordinator: WorkspaceCacheCoordinator) async {
        let tabLayout = store.tabLayoutAtom
        let workspacePane = store.paneAtom
        let repos = store.repositoryTopologyAtom.repos
        let watchedPaths = store.repositoryTopologyAtom.watchedPaths
        let activePaneRepoIds: Set<UUID> = {
            guard let activeTab = tabLayout.activeTab else { return [] }
            let repoIds = activeTab.activePaneIds.compactMap { workspacePane.pane($0)?.repoId }
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
