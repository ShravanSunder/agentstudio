import AppKit

@MainActor
extension PaneCoordinator {
    func resolvedWorktreeContext(
        for targetPane: Pane?
    ) -> (repo: Repo, worktree: Worktree)? {
        if let worktreeId = targetPane?.worktreeId,
            let repoId = targetPane?.repoId,
            let worktree = store.repositoryTopologyAtom.worktree(worktreeId),
            let repo = store.repositoryTopologyAtom.repo(repoId)
        {
            return (repo, worktree)
        }

        return store.repositoryTopologyAtom.repoAndWorktree(containing: targetPane?.metadata.facets.cwd)
    }

    func contextualBrowserMetadata(
        from pane: Pane,
        fallbackTitle: String
    ) -> (
        metadata: PaneMetadata,
        repo: Repo?,
        worktree: Worktree?
    ) {
        if let worktreeId = pane.worktreeId,
            let repoId = pane.repoId,
            let repo = store.repositoryTopologyAtom.repo(repoId),
            let worktree = store.repositoryTopologyAtom.worktree(worktreeId)
        {
            return (
                PaneMetadata(
                    contentType: .browser,
                    source: .worktree(
                        worktreeId: worktree.id, repoId: repo.id,
                        launchDirectory: worktree.path
                    ),
                    title: fallbackTitle,
                    facets: PaneContextFacets(
                        repoId: repo.id,
                        repoName: repo.name,
                        worktreeId: worktree.id,
                        worktreeName: worktree.name,
                        cwd: pane.metadata.cwd ?? worktree.path
                    )
                ),
                repo,
                worktree
            )
        }

        if let resolved = store.repositoryTopologyAtom.repoAndWorktree(containing: pane.metadata.cwd) {
            return (
                PaneMetadata(
                    contentType: .browser,
                    source: .worktree(
                        worktreeId: resolved.worktree.id, repoId: resolved.repo.id,
                        launchDirectory: resolved.worktree.path
                    ),
                    title: fallbackTitle,
                    facets: PaneContextFacets(
                        repoId: resolved.repo.id,
                        repoName: resolved.repo.name,
                        worktreeId: resolved.worktree.id,
                        worktreeName: resolved.worktree.name,
                        cwd: pane.metadata.cwd ?? resolved.worktree.path
                    )
                ),
                resolved.repo,
                resolved.worktree
            )
        }

        return (
            PaneMetadata(
                contentType: .browser,
                source: .floating(launchDirectory: nil, title: fallbackTitle),
                title: fallbackTitle
            ),
            nil,
            nil
        )
    }

    func executeInsertDrawerPane(
        parentPaneId: UUID,
        targetDrawerPaneId: UUID,
        direction: SplitNewDirection
    ) {
        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after

        let fallbackCWD =
            store.paneAtom.pane(parentPaneId)?.worktreeId.flatMap(store.repositoryTopologyAtom.worktree)?.path

        guard
            let drawerPane = store.paneAtom.insertDrawerPane(
                in: parentPaneId,
                at: targetDrawerPaneId,
                direction: layoutDirection,
                position: position,
                parentFallbackCWD: fallbackCWD
            )
        else {
            Self.logger.warning(
                "insertDrawerPane: failed to insert drawer pane under parent \(parentPaneId) at target \(targetDrawerPaneId)"
            )
            return
        }

        viewRegistry.ensureSlot(for: drawerPane.id)
        ensureTerminalPaneView(drawerPane)
        focusVisiblePaneHost(drawerPane.id)
    }

    func ensureTerminalPaneView(_ pane: Pane) {
        registerTerminalPlaceholderIfNeeded(for: pane, mode: .preparing)
        if createViewForContentUsingCurrentGeometry(pane: pane) == nil {
            RestoreTrace.log("ensureTerminalPaneView deferred pane=\(pane.id)")
            restoreViewsForActiveTabIfNeeded()
        }
    }

    func focusVisiblePaneHost(_ paneId: UUID) {
        if applyPaneRefocusIfReady(for: paneId) {
            pendingFocusPaneIds.remove(paneId)
        } else {
            pendingFocusPaneIds.insert(paneId)
        }
    }

    func handlePaneHostAttachedToWindow(_ paneId: UUID) {
        guard pendingFocusPaneIds.contains(paneId) else { return }
        if applyPaneRefocusIfReady(for: paneId) {
            pendingFocusPaneIds.remove(paneId)
        }
    }

    @discardableResult
    func focusPaneHostIfReady(_ paneId: UUID) -> Bool {
        applyPaneRefocusIfReady(for: paneId)
    }

    @discardableResult
    private func applyPaneRefocusIfReady(for paneId: UUID) -> Bool {
        let paneKind: PaneFocusContext.PaneKind
        if let pane = store.paneAtom.pane(paneId) {
            switch pane.content {
            case .terminal:
                paneKind = .terminal
            case .webview:
                paneKind = .webview
            case .bridgePanel:
                paneKind = .bridge
            case .codeViewer:
                paneKind = .codeViewer
            case .unsupported:
                paneKind = .unknown
            }
        } else {
            paneKind = .unknown
        }

        let decision = PaneFocusOrchestrator.decide(
            trigger: .refocusRequest(PaneRefocusRequestTrigger(reason: .explicit)),
            context: PaneFocusContext(
                activeTabId: store.tabLayoutAtom.activeTabId,
                activePaneId: paneId,
                activeDrawerParentPaneId: nil,
                activeDrawerPaneId: nil,
                targetPaneId: paneId,
                targetTabId: store.tabLayoutAtom.tabs.first { $0.paneIds.contains(paneId) }?.id,
                targetPaneKind: paneKind,
                targetPaneIsAlreadyActive: true,
                targetMountedContent: viewRegistry.view(for: paneId)?.mountedContentStateForPaneFocus ?? .unmounted,
                managementMode: atom(\.managementMode).isActive ? .active(scope: .mainRow) : .inactive,
                windowState: viewRegistry.view(for: paneId)?.window?.isKeyWindow == true ? .key : .background,
                triggerSource: .refocusRequest
            )
        )

        let paneFocusExecutor = PaneFocusExecutor(
            hostViewProvider: { [weak self] targetPaneId in
                self?.viewRegistry.view(for: targetPaneId)
            },
            hostViewsProvider: { [weak self] in
                guard let self else { return [] }
                return self.viewRegistry.registeredPaneIds.compactMap { self.viewRegistry.view(for: $0) }
            },
            syncRuntimeFocus: { [weak self] surfaceId in
                self?.surfaceManager.syncFocus(activeSurfaceId: surfaceId)
            }
        )

        return paneFocusExecutor.apply(decision)
    }

    func executeMergeTab(
        sourceTabId: UUID,
        targetTabId: UUID,
        targetPaneId: UUID,
        direction: SplitNewDirection
    ) {
        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after

        store.tabLayoutAtom.mergeTab(
            sourceId: sourceTabId,
            intoTarget: targetTabId,
            at: targetPaneId,
            direction: layoutDirection,
            position: position
        )
    }

    func executeRepair(_ repairAction: RepairAction) {
        switch repairAction {
        case .recreateSurface(let paneId):
            guard let pane = store.paneAtom.pane(paneId) else {
                Self.logger.warning("repair \(String(describing: repairAction)): pane not in store")
                return
            }
            teardownView(for: paneId, shouldUnregisterRuntime: false)
            guard createViewForRepair(for: pane) != nil else {
                Self.logger.error("repair recreateSurface failed for pane \(paneId)")
                return
            }
            Self.logger.info("Repaired view for pane \(paneId)")

        case .createMissingView(let paneId):
            guard let pane = store.paneAtom.pane(paneId) else {
                Self.logger.warning("repair \(String(describing: repairAction)): pane not in store")
                return
            }
            if let existingView = viewRegistry.view(for: paneId),
                existingView.mountedContent(as: TerminalPaneMountView.self)?.currentPlaceholderView == nil
            {
                Self.logger.info("repair createMissingView: pane \(paneId) already has a view")
                return
            }
            guard createViewForRepair(for: pane) != nil else {
                Self.logger.error("repair createMissingView failed for pane \(paneId)")
                return
            }
            Self.logger.info("Created missing view for pane \(paneId)")

        case .reattachZmx, .markSessionFailed, .cleanupOrphan:
            Self.logger.warning("repair: \(String(describing: repairAction)) — not yet implemented")
        }
    }

    /// Recreate a pane view during repair while preserving geometry requirements for terminals.
    /// Terminal panes must use trusted current geometry; non-terminal panes can be recreated directly.
    func createViewForRepair(for pane: Pane) -> NSView? {
        if case .terminal = pane.content {
            return createViewForContentUsingCurrentGeometry(pane: pane)
        }
        return createViewForContent(pane: pane)
    }

    /// Teardown views for all drawer panes owned by a parent pane.
    func teardownDrawerPanes(for parentPaneId: UUID) {
        guard let pane = store.paneAtom.pane(parentPaneId),
            let drawer = pane.drawer
        else { return }
        for drawerPaneId in drawer.paneIds {
            teardownView(for: drawerPaneId)
        }
    }

    /// Bridge SplitNewDirection → Layout.SplitDirection.
    func bridgeDirection(_ direction: SplitNewDirection) -> Layout.SplitDirection {
        switch direction {
        case .left, .right: return .horizontal
        case .up, .down: return .vertical
        }
    }
}
