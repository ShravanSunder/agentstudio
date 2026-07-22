import Foundation

struct BridgePaneProductFileSharedConstructionBinder: Sendable {
    private let coordinator: BridgeWorktreeProductConstructionCoordinator
    private let gitReadContext: BridgeGitReadContext
    private let preparationLoader: BridgePaneProductFileSnapshotPreparationLoader
    private let snapshotBuilder: BridgePaneProductFileSharedSnapshotBuilder
    private let worktree: Worktree

    init(
        coordinator: BridgeWorktreeProductConstructionCoordinator,
        gitReadContext: BridgeGitReadContext,
        preparationLoader: @escaping BridgePaneProductFileSnapshotPreparationLoader,
        snapshotBuilder: @escaping BridgePaneProductFileSharedSnapshotBuilder,
        worktree: Worktree
    ) {
        self.coordinator = coordinator
        self.gitReadContext = gitReadContext
        self.preparationLoader = preparationLoader
        self.snapshotBuilder = snapshotBuilder
        self.worktree = worktree
    }

    func acquire(
        openedSource: BridgeWorktreeFileOpenedSource
    ) async throws -> BridgeSharedFileSnapshotConsumerLease {
        let key = BridgeFileConstructionKey(
            owner: BridgeWorktreeProductOwnerKey(
                repoIdentity: worktree.repoId.uuidString,
                worktreeIdentity: worktree.id.uuidString,
                stableRootIdentity: StableKey.fromPath(worktree.path),
                providerIdentity: "agentstudio-git-file-manifest-v1"
            ),
            canonicalWorkingDirectoryIdentity: openedSource.canonicalCwdScope,
            pathScope: openedSource.canonicalPathScope,
            statusSemantics: BridgeFileStatusSemanticsKey(
                includesUntracked: true,
                includesIgnored: false,
                detectsRenames: true,
                recursesUntrackedDirectories: true
            ),
            ignoreSemantics: BridgeFileIgnoreSemanticsKey(
                respectsRepositoryIgnore: true,
                respectsInfoExclude: true,
                respectsGlobalIgnore: false,
                additionalPatternIdentity: nil
            )
        )
        let preparationLoader = preparationLoader
        let snapshotBuilder = snapshotBuilder
        let gitReadContext = gitReadContext
        let request = BridgeWorktreeFileMaterializationRequest(
            rootURL: worktree.path,
            openedSource: openedSource
        )
        return try await coordinator.acquireProgressiveFile(key: key) { context, publisher in
            let constructionGitReadContext = BridgeGitReadContext(
                scheduler: gitReadContext.scheduler,
                worktreeKey: gitReadContext.worktreeKey,
                scopeKey: BridgeGitReadScopeKey(
                    token:
                        "file-construction:\(gitReadContext.worktreeKey.token):epoch:\(context.epoch.rawValue)"
                )
            )
            let preparation = await preparationLoader(
                request.rootURL,
                constructionGitReadContext
            )
            return try await snapshotBuilder(request, preparation, publisher)
        }
    }

    func preparation(
        for lease: BridgeSharedFileSnapshotConsumerLease
    ) async throws -> BridgeSharedFileSnapshotPreparation {
        try await coordinator.readFileSnapshotPreparation(for: lease)
    }

    func nextRead(
        for lease: BridgeSharedFileSnapshotConsumerLease,
        cursor: BridgeSharedFileSnapshotCursor
    ) async throws -> BridgeSharedFileSnapshotRead {
        try await coordinator.nextFileSnapshotRead(for: lease, cursor: cursor)
    }

    func release(_ lease: BridgeSharedFileSnapshotConsumerLease) async {
        await coordinator.release(lease)
    }
}
