import AgentStudioCore
import AgentStudioProgrammaticControl
import Foundation
import os

private let bridgeFileCollectionLogger = Logger(subsystem: "com.agentstudio", category: "BridgeFileCollection")

typealias BridgeFileCollectionMemberFactory =
    @Sendable (Worktree) -> BridgeFileCollectionMemberSource

extension BridgePaneController {
    /// Build one member's own per-worktree File source: its worktree authority,
    /// its Git reads keyed by its own root, and the pane's read scope.
    nonisolated static func makeFileCollectionMemberFactory(
        paneId: UUID,
        gitReadScheduler: BridgeGitReadScheduler?,
        constructionCoordinator: BridgeWorktreeProductConstructionCoordinator?,
        statusProvider: (any GitWorkingTreeStatusProvider)?
    ) -> BridgeFileCollectionMemberFactory? {
        guard let gitReadScheduler, let constructionCoordinator, let statusProvider else { return nil }
        return { worktree in
            BridgeFileCollectionMemberSource(
                worktreeId: worktree.id,
                rootURL: worktree.path,
                memberCollectionToken: worktree.stableKey,
                producer: BridgePaneProductFileMetadataSource(
                    authority: BridgePaneProductFileSourceAuthority(paneId: paneId, worktree: worktree),
                    gitReadContext: BridgeGitReadContext(
                        scheduler: gitReadScheduler,
                        worktreeKey: BridgeGitReadWorktreeKey(token: worktree.stableKey),
                        scopeKey: BridgeGitReadScopeKey(token: paneId.uuidString)
                    ),
                    constructionCoordinator: constructionCoordinator,
                    statusProvider: statusProvider
                )
            )
        }
    }

    nonisolated static func fileCollectionMembers(
        _ worktrees: [Worktree],
        paneId: UUID,
        input: BridgeProductSessionDependencyInput
    ) -> [BridgeFileCollectionMemberSource] {
        guard
            let factory = makeFileCollectionMemberFactory(
                paneId: paneId,
                gitReadScheduler: input.fileGitReadScheduler,
                constructionCoordinator: input.worktreeProductConstructionCoordinator,
                statusProvider: input.gitWorkingTreeStatusProvider
            )
        else { return [] }
        return worktrees.map(factory)
    }

    /// Whether this controller reads `worktreeId` as a Files member or as its
    /// Review member; refresh routing follows these explicit bindings.
    package func readsWorktree(_ worktreeId: UUID) -> Bool {
        reviewBinding?.worktreeId == worktreeId
            || filesBinding?.members.contains { $0.id == worktreeId } == true
    }

    /// The Files collection key of a member worktree's relative path, as the
    /// viewer lists it.
    package func fileCollectionDisplayPath(worktreeId: UUID, relativePath: String) async -> String? {
        await fileCollectionSource?.displayPath(worktreeId: worktreeId, relativePath: relativePath)
    }

    // S9: receiver-addressed IPC replaces this first-member reading.
    /// `bridge.fileTree.revealPath` keeps its worktree-relative contract: the
    /// path is read against the receiver's first member and handed to the page
    /// as that member's Files key. A path the collection does not list is not
    /// found; it is never matched against display keys as-is.
    func fileCollectionAddressedPageControl(
        _ command: IPCBridgePageControlCommand
    ) async throws -> IPCBridgePageControlCommand {
        guard case .fileTreeRevealPath(let relativePath) = command else { return command }
        guard let firstMember = filesBinding?.members.first,
            let displayPath = await fileCollectionDisplayPath(
                worktreeId: firstMember.id,
                relativePath: relativePath
            )
        else {
            throw BridgeIPCProjectionError(reason: .itemNotFound)
        }
        return .fileTreeRevealPath(path: displayPath)
    }

    /// Queue a Files input update behind any update still being delivered.
    /// Equal bindings are suppressed here, so repeated topology passes cost
    /// one value comparison per mounted Bridge and never wake the collection.
    package func enqueueFilesSourceUpdate(_ binding: BridgeFilesSourceBinding) {
        guard binding != latestRequestedFilesBinding else { return }
        latestRequestedFilesBinding = binding
        let preceding = filesSourceUpdateTail
        filesSourceUpdateTail = Task { [weak self] in
            await preceding?.value
            await self?.applyFilesSource(binding)
        }
    }

    /// Update the mounted Files collection to a new membership and opened-
    /// document inventory. Surviving sources, keys, selection and descriptors
    /// stay untouched; only the difference reaches the worker.
    package func applyFilesSource(_ binding: BridgeFilesSourceBinding) async {
        guard binding != filesBinding, let fileCollectionSource,
            binding.collectionToken == filesBinding?.collectionToken
        else { return }
        filesBinding = binding
        let factory = Self.makeFileCollectionMemberFactory(
            paneId: paneId,
            gitReadScheduler: fileGitReadScheduler,
            constructionCoordinator: worktreeProductConstructionCoordinator,
            statusProvider: gitWorkingTreeStatusProvider
        )
        do {
            try await fileCollectionSource.applyMembership(
                members: factory.map { binding.members.map($0) } ?? [],
                openedDocuments: binding.openedDocuments
            )
        } catch {
            // A failed delivery leaves the worker's File stream to its existing
            // reset and recovery path; the collection itself is already current.
            bridgeFileCollectionLogger.warning("Bridge Files membership update did not reach pane \(self.paneId)")
        }
        // The File surface's annotations follow its members and loose opened
        // documents; observers of this collection recapture their catalog.
        if let worktreeAnnotationStore,
            let annotationScope = try? await fileCollectionSource.worktreeAnnotationScope()
        {
            await worktreeAnnotationStore.updateObservedScope(annotationScope)
        }
    }
}
