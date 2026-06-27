import AppKit

@MainActor
extension WorkspaceSurfaceCoordinator {
    /// Open a read-only Bridge review pane in a new tab.
    @discardableResult
    func openBridgeReview(worktreeId: UUID? = nil) -> Pane? {
        let activePane = store.tabLayoutAtom.activeTabId
            .flatMap { store.tabLayoutAtom.tab($0)?.activePaneId }
            .flatMap { store.paneAtom.pane($0) }
        guard let context = bridgeReviewMetadata(from: activePane, worktreeId: worktreeId) else {
            return nil
        }
        let state = BridgePaneState(panelKind: .diffViewer, source: context.source)
        let pane = store.paneAtom.createPane(
            content: .bridgePanel(state),
            metadata: context.metadata
        )
        viewRegistry.ensureSlot(for: pane.id)

        guard createViewForContent(pane: pane) != nil else {
            Self.logger.error("Bridge review creation failed — rolling back pane \(pane.id)")
            store.mutationCoordinator.removePane(pane.id)
            // Safe immediate deletion: creation failed before the pane entered a rendered layout.
            viewRegistry.removeSlot(for: pane.id)
            return nil
        }

        let tab = Tab(paneId: pane.id, name: tabNameForPane(pane))
        store.tabLayoutAtom.appendTab(tab)
        store.tabLayoutAtom.setActiveTab(tab.id)

        Self.logger.info("Opened Bridge review pane \(pane.id)")
        return pane
    }

    #if DEBUG
        /// Open a deterministic Bridge review pane for local observability proof.
        @discardableResult
        func openBridgeReviewObservabilitySmoke() -> Pane? {
            let state = BridgePaneState(panelKind: .diffViewer, source: nil)
            let pane = store.paneAtom.createPane(
                content: .bridgePanel(state),
                metadata: PaneMetadata(
                    contentType: .diff,
                    title: "Bridge Observability Smoke"
                )
            )
            bridgeReviewSourceProviderOverridesByPaneId[pane.id] = BridgeObservabilitySmokeReviewSourceProvider()
            viewRegistry.ensureSlot(for: pane.id)

            guard createViewForContent(pane: pane) != nil else {
                Self.logger.error("Bridge observability smoke creation failed — rolling back pane \(pane.id)")
                bridgeReviewSourceProviderOverridesByPaneId[pane.id] = nil
                store.mutationCoordinator.removePane(pane.id)
                viewRegistry.removeSlot(for: pane.id)
                return nil
            }

            let tab = Tab(paneId: pane.id, name: tabNameForPane(pane))
            store.tabLayoutAtom.appendTab(tab)
            store.tabLayoutAtom.setActiveTab(tab.id)

            Self.logger.info("Opened Bridge observability smoke pane \(pane.id)")
            return pane
        }
    #endif

    private func bridgeReviewMetadata(
        from activePane: Pane?,
        worktreeId: UUID?
    ) -> (metadata: PaneMetadata, source: BridgePaneSource?)? {
        if let worktreeId {
            guard
                let worktree = store.repositoryTopologyAtom.worktree(worktreeId),
                let repo = store.repositoryTopologyAtom.repo(containing: worktreeId)
            else {
                return nil
            }
            return bridgeReviewMetadata(repo: repo, worktree: worktree, cwd: worktree.path)
        }

        guard let resolved = resolvedWorktreeContext(for: activePane) else {
            return (
                PaneMetadata(
                    contentType: .diff,
                    title: "Bridge Review"
                ),
                nil
            )
        }

        let cwd = activePane?.metadata.cwd ?? resolved.worktree.path
        return bridgeReviewMetadata(repo: resolved.repo, worktree: resolved.worktree, cwd: cwd)
    }

    private func bridgeReviewMetadata(
        repo: Repo,
        worktree: Worktree,
        cwd: URL
    ) -> (metadata: PaneMetadata, source: BridgePaneSource?) {
        let metadata = PaneMetadata(
            contentType: .diff,
            launchDirectory: worktree.path,
            title: "Bridge Review",
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: repo.name,
                worktreeId: worktree.id,
                worktreeName: worktree.name,
                cwd: cwd
            )
        )
        return (
            metadata,
            .workspace(rootPath: worktree.path.path, baseline: defaultBridgeReviewBaseline(for: repo))
        )
    }

    private func defaultBridgeReviewBaseline(for _: Repo) -> WorkspaceBaseline {
        .ref(name: "HEAD")
    }
}
