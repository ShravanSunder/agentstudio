import AppKit

@MainActor
extension PaneCoordinator {
    /// Open a read-only Bridge review pane in a new tab.
    @discardableResult
    func openBridgeReview() -> Pane? {
        let activePane = store.tabLayoutAtom.activeTabId
            .flatMap { store.tabLayoutAtom.tab($0)?.activePaneId }
            .flatMap { store.paneAtom.pane($0) }
        let context = bridgeReviewMetadata(from: activePane)
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
        from activePane: Pane?
    ) -> (metadata: PaneMetadata, source: BridgePaneSource?) {
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
        let metadata = PaneMetadata(
            contentType: .diff,
            launchDirectory: resolved.worktree.path,
            title: "Bridge Review",
            facets: PaneContextFacets(
                repoId: resolved.repo.id,
                repoName: resolved.repo.name,
                worktreeId: resolved.worktree.id,
                worktreeName: resolved.worktree.name,
                cwd: cwd
            )
        )
        return (
            metadata,
            .workspace(rootPath: resolved.worktree.path.path, baseline: .unstaged)
        )
    }
}
