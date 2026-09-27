import AgentStudioBridge
import AgentStudioCore
import Foundation

enum BridgeDevelopmentServerCoreCompositionError: Error, Equatable {
    case databasePreparationFailed
    case paneIsNotBridge
    case paneIsNotWorkspaceBacked
    case paneMissingAfterSeed
    case repositoryMissing
    case restoredWorktreeDoesNotMatchSeed
    case topologyFlushFailed
    case topologyIdentityMissing
    case workspaceLoadFailed
    case workspaceFlushFailed
}

@MainActor
final class BridgeDevelopmentServerCoreComposition {
    let productSource: BridgeDevelopmentProductSource
    let worktreeAnnotationOutputCoordinator: WorktreeAnnotationOutputCoordinatorActor
    let worktreeAnnotationStore: WorktreeAnnotationServiceActor

    private let atoms: CoreAtoms
    private let repositoryTopologyStore: RepositoryTopologyStore
    private let workspaceStore: WorkspaceStore
    private var isShutdown = false

    private init(
        atoms: CoreAtoms,
        productSource: BridgeDevelopmentProductSource,
        repositoryTopologyStore: RepositoryTopologyStore,
        workspaceStore: WorkspaceStore,
        worktreeAnnotationOutputCoordinator: WorktreeAnnotationOutputCoordinatorActor,
        worktreeAnnotationStore: WorktreeAnnotationServiceActor
    ) {
        self.atoms = atoms
        self.productSource = productSource
        self.repositoryTopologyStore = repositoryTopologyStore
        self.workspaceStore = workspaceStore
        self.worktreeAnnotationOutputCoordinator = worktreeAnnotationOutputCoordinator
        self.worktreeAnnotationStore = worktreeAnnotationStore
    }

    static func prepare(
        configuration: BridgeDevelopmentServerConfiguration
    ) async throws -> BridgeDevelopmentServerCoreComposition {
        try FileManager.default.createDirectory(
            at: configuration.dataRoot,
            withIntermediateDirectories: true
        )
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: configuration.dataRoot.appending(path: "core.sqlite"),
            localDatabaseURL: configuration.dataRoot.appending(path: "local.sqlite"),
            localDatabaseReplacementObserver: WorktreeAnnotationRecoveryWitnessWriter.write
        ).makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            throw BridgeDevelopmentServerCoreCompositionError.databasePreparationFailed
        }

        let atoms = CoreAtoms()
        let workspaceStore = WorkspaceStore(
            identityAtom: atoms.workspaceIdentity,
            windowMemoryAtom: atoms.workspaceWindowMemory,
            repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
            paneAtom: atoms.workspacePane,
            tabLayoutAtom: atoms.workspaceTabLayout,
            mutationCoordinator: atoms.workspaceMutationCoordinator,
            bridgeNavigationAtom: atoms.bridgeNavigation,
            sqliteDatastore: datastore
        )
        switch await workspaceStore.loadCanonicalComposition() {
        case .loaded, .initializedDefaultWorkspace:
            break
        case .failed:
            throw BridgeDevelopmentServerCoreCompositionError.workspaceLoadFailed
        }
        let repositoryTopologyStore = RepositoryTopologyStore(
            atom: atoms.workspaceRepositoryTopology,
            sqliteDatastore: datastore
        )

        if atoms.workspacePane.pane(configuration.paneID) == nil {
            try await seedDevelopmentPane(
                configuration: configuration, atoms: atoms, workspaceStore: workspaceStore,
                repositoryTopologyStore: repositoryTopologyStore, datastore: datastore)
        }

        let productSource = try restoredProductSource(
            atoms: atoms,
            configuration: configuration
        )
        let annotationOwners = await makeAnnotationOwners(
            workspaceStore: workspaceStore,
            datastore: datastore,
            dataRoot: configuration.dataRoot
        )
        workspaceStore.startObserving()
        repositoryTopologyStore.startObserving()
        return BridgeDevelopmentServerCoreComposition(
            atoms: atoms,
            productSource: productSource,
            repositoryTopologyStore: repositoryTopologyStore,
            workspaceStore: workspaceStore,
            worktreeAnnotationOutputCoordinator: annotationOwners.outputCoordinator,
            worktreeAnnotationStore: annotationOwners.store
        )
    }

    /// The seeded pane is a standalone receiver reviewing the seed worktree
    /// against the configured comparison.
    private static func seedDevelopmentPane(
        configuration: BridgeDevelopmentServerConfiguration,
        atoms: CoreAtoms,
        workspaceStore: WorkspaceStore,
        repositoryTopologyStore: RepositoryTopologyStore,
        datastore: WorkspaceSQLiteDatastoreActor
    ) async throws {
        let worktree = atoms.workspaceMutationCoordinator.ensureMainWorktree(
            at: configuration.seedWorktreeRoot
        )
        guard let repository = atoms.workspaceRepositoryTopology.repo(worktree.repoId) else {
            throw BridgeDevelopmentServerCoreCompositionError.repositoryMissing
        }
        let paneState = BridgePaneState(panelKind: .diffViewer)
        atoms.workspacePane.addPane(
            Pane(
                id: configuration.paneID,
                content: .bridgePanel(paneState),
                metadata: PaneMetadata(
                    paneId: PaneId(existingUUID: configuration.paneID),
                    contentType: .diff,
                    launchDirectory: worktree.path,
                    title: "Bridge development review",
                    facets: PaneContextFacets(
                        repoId: repository.id,
                        repoName: repository.name,
                        worktreeId: worktree.id,
                        worktreeName: worktree.name,
                        cwd: worktree.path
                    )
                )
            )
        )
        atoms.workspaceTabLayout.appendTab(
            Tab(paneId: configuration.paneID, name: "Bridge development review")
        )
        // The pane graph must be durable before its receiver contribution
        // can be admitted against an effect-point owner snapshot.
        guard await workspaceStore.flushAsync() == .persisted else {
            throw BridgeDevelopmentServerCoreCompositionError.workspaceFlushFailed
        }
        do {
            try await repositoryTopologyStore.flushAsync()
        } catch {
            throw BridgeDevelopmentServerCoreCompositionError.topologyFlushFailed
        }
        let receiver = BridgeReceiver.standalone(configuration.paneID)
        let topologySnapshot = BridgeReceiverTopologySnapshot(
            sourcePaneId: configuration.paneID,
            paneStatesByID: atoms.workspacePane.captureBridgeLinkPaneFacts(),
            companionEntriesBySourceID: atoms.workspacePanePresentation.zoomCompanionsBySourcePaneId,
            repositoryTopology: atoms.workspaceRepositoryTopology.captureReadSnapshot()
        )
        let committed = try await datastore.commitBridgeMemberAddition(
            context: BridgeLinkMutationContext(
                workspaceID: atoms.workspaceIdentity.workspaceId,
                receiver: receiver,
                generation: workspaceStore.bridgeWriteSequencer.nextTicket().value,
                topologySnapshot: topologySnapshot
            ),
            worktreeID: worktree.id,
            contributor: .app,
            addedAt: Date()
        )
        switch committed.result {
        case .added, .alreadyPresent: break
        case .refusedUnknownWorktree, .staleOwner, .staleReceiver, .unsupportedReceiver:
            throw BridgeDevelopmentServerCoreCompositionError.paneIsNotWorkspaceBacked
        }
        let navigationRecord = try await preparedReviewNavigationRecord(
            committed.record,
            worktreeID: worktree.id,
            contributionTarget: configuration.seedContributionTarget
        )
        atoms.bridgeNavigation.setRecord(navigationRecord, for: receiver)
        guard await workspaceStore.flushAsync() == .persisted else {
            throw BridgeDevelopmentServerCoreCompositionError.workspaceFlushFailed
        }
    }

    @concurrent nonisolated private static func preparedReviewNavigationRecord(
        _ committed: BridgeNavigationRecord,
        worktreeID: UUID,
        contributionTarget: WorkspaceReviewContributionTarget
    ) async throws -> BridgeNavigationRecord {
        guard
            case .applied(let navigationRecord) = BridgeNavigationRules.activatingReview(
                of: worktreeID,
                comparison: WorkspaceBaseline(contributionTarget: contributionTarget),
                in: committed
            )
        else {
            throw BridgeDevelopmentServerCoreCompositionError.paneIsNotWorkspaceBacked
        }
        return navigationRecord
    }

    private static func makeAnnotationOwners(
        workspaceStore: WorkspaceStore,
        datastore: WorkspaceSQLiteDatastoreActor,
        dataRoot: URL
    ) async -> (store: WorktreeAnnotationServiceActor, outputCoordinator: WorktreeAnnotationOutputCoordinatorActor) {
        let store = WorktreeAnnotationServiceActor(
            sqliteAdapter: WorktreeAnnotationSQLiteDatastoreAdapter(
                workspaceID: workspaceStore.identityAtom.workspaceId,
                datastore: datastore
            )
        )
        let outputCoordinator = WorktreeAnnotationOutputCoordinatorActor(
            store: store,
            effect: BridgeDevelopmentWorktreeAnnotationOutputEffect(dataRoot: dataRoot)
        )
        _ = await store.restoreRecoveryState()
        return (store, outputCoordinator)
    }

    func applyContributionTarget(
        _ target: WorkspaceReviewContributionTarget
    ) -> BridgeReviewComparisonCommitResult {
        let receiver = BridgeReceiver.standalone(productSource.paneID)
        guard let record = atoms.bridgeNavigation.record(for: receiver) else {
            return .receiverUnavailable
        }
        let comparison = WorkspaceBaseline(contributionTarget: target)
        guard record.reviewComparisonsByWorktreeId[productSource.worktreeID] != comparison else {
            return .unchanged(comparison)
        }
        switch BridgeNavigationRules.recordingReviewComparison(
            comparison,
            for: productSource.worktreeID,
            in: record
        ) {
        case .applied(let updated):
            atoms.bridgeNavigation.setRecord(updated, for: receiver)
            return .applied(comparison)
        case .notMember:
            return .receiverUnavailable
        }
    }

    func shutdown() async throws {
        guard !isShutdown else { return }
        isShutdown = true
        guard await workspaceStore.flushAsync() == .persisted else {
            throw BridgeDevelopmentServerCoreCompositionError.workspaceFlushFailed
        }
        do {
            try await repositoryTopologyStore.flushAsync()
        } catch {
            throw BridgeDevelopmentServerCoreCompositionError.topologyFlushFailed
        }
    }

    private static func restoredProductSource(
        atoms: CoreAtoms,
        configuration: BridgeDevelopmentServerConfiguration
    ) throws -> BridgeDevelopmentProductSource {
        guard let pane = atoms.workspacePane.pane(configuration.paneID) else {
            throw BridgeDevelopmentServerCoreCompositionError.paneMissingAfterSeed
        }
        guard case .bridgePanel = pane.content else {
            throw BridgeDevelopmentServerCoreCompositionError.paneIsNotBridge
        }
        guard
            let record = atoms.bridgeNavigation.record(for: .standalone(pane.id)),
            let reviewWorktreeID = record.reviewSelection.memberWorktreeId
        else {
            throw BridgeDevelopmentServerCoreCompositionError.paneIsNotWorkspaceBacked
        }
        guard let repoID = pane.metadata.repoId,
            let worktreeID = pane.metadata.worktreeId,
            let repository = atoms.workspaceRepositoryTopology.repo(repoID),
            let worktree = atoms.workspaceRepositoryTopology.worktree(worktreeID),
            worktree.repoId == repository.id
        else {
            throw BridgeDevelopmentServerCoreCompositionError.topologyIdentityMissing
        }
        let topologyRoot = worktree.path.standardizedFileURL.resolvingSymlinksInPath()
        guard reviewWorktreeID == worktree.id,
            topologyRoot.path == configuration.seedWorktreeRoot.path
        else {
            throw BridgeDevelopmentServerCoreCompositionError.restoredWorktreeDoesNotMatchSeed
        }
        return BridgeDevelopmentProductSource(
            paneID: pane.id,
            reviewComparison: record.reviewComparisonsByWorktreeId[worktree.id],
            repoID: repository.id,
            reviewedSubjectLabel: pane.metadata.worktreeName ?? pane.metadata.checkoutRef,
            worktreeID: worktree.id,
            worktreeRoot: topologyRoot
        )
    }
}
