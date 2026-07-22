import AppKit

@MainActor
extension WorkspaceSurfaceCoordinator {
    /// Open an independent read-only Bridge review pane in a new tab.
    @discardableResult
    func openBridgeReviewInNewTab(worktreeId: UUID? = nil) -> Pane? {
        openBridgePane(
            panelKind: .diffViewer,
            title: "Bridge Review",
            worktreeId: worktreeId,
            logName: "Bridge review"
        )
    }

    /// Open an independent Bridge file-viewer pane in a new tab.
    @discardableResult
    func openBridgeFilesInNewTab(worktreeId: UUID? = nil) -> Pane? {
        openBridgePane(
            panelKind: .fileViewer,
            title: "Files",
            worktreeId: worktreeId,
            logName: "Bridge file view"
        )
    }

    func resolveBridgePaneCommand(worktreeId: UUID? = nil) -> BridgePaneCommandTarget? {
        let activePane = store.tabLayoutAtom.activeTabId
            .flatMap { store.tabLayoutAtom.tab($0)?.activePaneId }
            .flatMap { store.paneAtom.pane($0) }
        guard let context = bridgeReviewMetadata(from: activePane, worktreeId: worktreeId),
            let resolvedWorktreeId = context.metadata.facets.worktreeId
        else {
            return nil
        }

        let activeTabId = store.tabLayoutAtom.activeTabId
        let activePaneId = activeTabId.flatMap { store.tabLayoutAtom.tab($0)?.activePaneId }
        let locations = atom(\.workspaceLookup).paneLocations(
            for: resolvedWorktreeId,
            workspacePane: store.paneAtom,
            workspaceTab: WorkspaceTabLayoutDerived(
                shellAtom: store.tabShellAtom,
                arrangementAtom: store.tabArrangementAtom
            )
        )
        let candidates = locations.compactMap { location -> BridgePaneCommandCandidate? in
            guard let pane = store.paneAtom.pane(location.paneId) else { return nil }
            let isBridgePane: Bool
            if case .bridgePanel = pane.content {
                isBridgePane = true
            } else {
                isBridgePane = false
            }
            return BridgePaneCommandCandidate(
                paneId: pane.id,
                worktreeId: resolvedWorktreeId,
                isBridgePane: isBridgePane,
                isPaneActive: pane.residency == .active,
                isCurrentActivePane: activeTabId == location.tabId && activePaneId == pane.id,
                attendanceOrdinal: atom(\.bridgePaneAttendance).ordinal(for: pane.id),
                tabIndex: location.tabIndex,
                paneIndexInTab: location.paneIndexInTab
            )
        }
        return BridgePaneCommandTarget(
            worktreeId: resolvedWorktreeId,
            resolution: BridgePaneCommandResolver.resolve(
                worktreeId: resolvedWorktreeId,
                candidates: candidates
            )
        )
    }

    @discardableResult
    func requestBridgePaneSurface(_ surface: BridgeProductSurface, paneId: UUID) -> Bool {
        guard
            let controller = viewRegistry.view(for: paneId)?
                .mountedContent(as: BridgePaneMountView.self)?
                .controller
        else {
            return false
        }
        return controller.requestViewerSurface(surface)
    }

    @discardableResult
    private func openBridgePane(
        panelKind: BridgePanelKind,
        title: String,
        worktreeId: UUID?,
        logName: String
    ) -> Pane? {
        let activePane = store.tabLayoutAtom.activeTabId
            .flatMap { store.tabLayoutAtom.tab($0)?.activePaneId }
            .flatMap { store.paneAtom.pane($0) }
        guard let context = bridgeReviewMetadata(from: activePane, worktreeId: worktreeId) else {
            return nil
        }
        let state = BridgePaneState(panelKind: panelKind, source: context.source)
        var metadata = context.metadata
        metadata.updateTitle(title)
        let pane = store.paneAtom.createPane(
            content: .bridgePanel(state),
            metadata: metadata
        )
        viewRegistry.ensureSlot(for: pane.id)

        guard createViewForContent(pane: pane) != nil else {
            Self.logger.error("\(logName) creation failed — rolling back pane \(pane.id)")
            store.mutationCoordinator.removePane(pane.id)
            // Safe immediate deletion: creation failed before the pane entered a rendered layout.
            viewRegistry.removeSlot(for: pane.id)
            return nil
        }

        let tab = Tab(paneId: pane.id, name: tabNameForPane(pane))
        store.tabLayoutAtom.appendTab(tab)
        store.tabLayoutAtom.setActiveTab(tab.id)
        refreshBridgePaneActivities()

        Self.logger.info("Opened \(logName) pane \(pane.id)")
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
            guard let onlyRegisteredContext = onlyRegisteredWorktreeContext() else {
                return nil
            }
            return bridgeReviewMetadata(
                repo: onlyRegisteredContext.repo,
                worktree: onlyRegisteredContext.worktree,
                cwd: onlyRegisteredContext.worktree.path
            )
        }

        let cwd = activePane?.metadata.cwd ?? resolved.worktree.path
        return bridgeReviewMetadata(repo: resolved.repo, worktree: resolved.worktree, cwd: cwd)
    }

    private func onlyRegisteredWorktreeContext() -> (repo: Repo, worktree: Worktree)? {
        let contexts = store.repositoryTopologyAtom.repos.flatMap { repo in
            repo.worktrees.map { worktree in
                (repo: repo, worktree: worktree)
            }
        }
        return contexts.count == 1 ? contexts[0] : nil
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
        .localDefaultBranch(branchName: "main")
    }
}
