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
                    launchDirectory: worktree.path,
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
                    launchDirectory: resolved.worktree.path,
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
                title: fallbackTitle
            ),
            nil,
            nil
        )
    }

    func executeInsertDrawerPane(
        parentPaneId: UUID,
        targetDrawerPaneId: UUID,
        direction: SplitNewDirection,
        sizingMode: DropSizingMode
    ) {
        let fallbackCWD =
            store.paneAtom.pane(parentPaneId)?.worktreeId.flatMap(store.repositoryTopologyAtom.worktree)?.path

        guard
            let drawerPane = store.paneAtom.insertDrawerPane(
                in: parentPaneId,
                at: targetDrawerPaneId,
                direction: direction,
                sizingMode: sizingMode,
                parentFallbackCWD: fallbackCWD
            )
        else {
            Self.logger.warning(
                "insertDrawerPane: failed to insert drawer pane under parent \(parentPaneId) at target \(targetDrawerPaneId)"
            )
            return
        }

        if let tabId = store.tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
            let drawerId = store.paneAtom.pane(parentPaneId)?.drawer?.drawerId
        {
            store.tabArrangementAtom.addDrawerPaneView(
                drawerId: drawerId,
                parentPaneId: parentPaneId,
                drawerPaneId: drawerPane.id,
                inTab: tabId,
                targetDrawerPaneId: targetDrawerPaneId,
                direction: direction,
                sizingMode: sizingMode
            )
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

    func restoreVisiblePaneIfNeeded(_ paneId: UUID, forceWhenBoundsExist: Bool = false) {
        guard let activeTab = store.tabLayoutAtom.activeTab else { return }
        if !windowLifecycleStore.isLaunchLayoutSettled {
            let hasPreparingPlaceholder =
                viewRegistry.terminalStatusPlaceholderView(for: paneId)?.shouldRetryCreationWhenBoundsChange == true
            guard forceWhenBoundsExist || hasPreparingPlaceholder || windowLifecycleStore.isReadyForLaunchRestore else {
                RestoreTrace.log(
                    "restoreVisiblePaneIfNeeded skipped launchLayoutUnsettled pane=\(paneId) bounds=\(NSStringFromRect(windowLifecycleStore.terminalContainerBounds)) settled=\(windowLifecycleStore.isLaunchLayoutSettled)"
                )
                return
            }
        }

        let terminalContainerBounds = windowLifecycleStore.terminalContainerBounds
        guard !terminalContainerBounds.isEmpty else {
            RestoreTrace.log("restoreVisiblePaneIfNeeded skipped boundsUnavailable pane=\(paneId)")
            return
        }

        let runtimePaneId = PaneId(uuid: paneId)
        guard visibilityTierResolver.tier(for: runtimePaneId) == .p0Visible else { return }
        guard let pane = store.paneAtom.pane(paneId) else { return }
        guard store.tabLayoutAtom.tabContaining(paneId: pane.parentPaneId ?? pane.id)?.id == activeTab.id else {
            return
        }

        if let placeholder = viewRegistry.terminalStatusPlaceholderView(for: paneId) {
            guard placeholder.shouldRetryCreationWhenBoundsChange else { return }
        } else if viewRegistry.view(for: paneId) != nil {
            return
        }

        let resolvedPaneFramesByTabId = resolveInitialFramesByTabId(in: terminalContainerBounds)
        _ = createViewForContent(
            pane: pane,
            initialFrame: initialFrame(for: pane, resolvedPaneFramesByTabId: resolvedPaneFramesByTabId),
            treatAsRestoredSessionStart: true
        )
    }

    func focusVisiblePaneHost(_ paneId: UUID) {
        if applyPaneRefocusIfReady(for: paneId) {
            pendingFocusPaneIds.remove(paneId)
        } else {
            pendingFocusPaneIds.insert(paneId)
        }
    }

    @discardableResult
    func clearFirstResponderToWindowContent(for paneId: UUID) -> Bool {
        let window = viewRegistry.view(for: paneId)?.window ?? NSApplication.shared.keyWindow
        guard let window, let contentView = window.contentView else { return false }
        pendingFocusPaneIds.remove(paneId)
        return window.makeFirstResponder(contentView)
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
        let paneKind = PaneFocusContext.PaneKind(content: store.paneAtom.pane(paneId)?.content)

        let decision = PaneFocusOrchestrator.decide(
            trigger: .refocusRequest(PaneRefocusRequestTrigger(reason: .explicit)),
            context: PaneFocusContext(
                activeTabId: store.tabLayoutAtom.activeTabId,
                activePaneId: paneId,
                activeDrawer: nil,
                targetPaneId: paneId,
                targetTabId: store.tabLayoutAtom.tabs.first { $0.paneIds.contains(paneId) }?.id,
                targetPaneKind: paneKind,
                targetPaneIsAlreadyActive: true,
                targetMountedContent: viewRegistry.view(for: paneId)?.mountedContentStateForPaneFocus ?? .unmounted,
                managementLayer: atom(\.managementLayer).isActive ? .active(scope: .mainRow) : .inactive,
                windowState: viewRegistry.view(for: paneId)?.window?.isKeyWindow == true ? .key : .background
            )
        )

        guard case .refocusRequest(let refocusDecision) = decision else {
            Self.logger.error("pane refocus produced non-refocus decision for pane \(paneId)")
            return false
        }

        return makeRefocusOnlyPaneFocusExecutor().apply(.refocusRequest(refocusDecision))
    }

    private func makeRefocusOnlyPaneFocusExecutor() -> PaneFocusExecutor {
        // Refocus decisions never carry selection actions, so these no-op
        // closures are intentional and keep the coordinator path limited to
        // responder/runtime repair work only.
        PaneFocusExecutor(
            hostViewProvider: { [weak self] targetPaneId in
                self?.viewRegistry.view(for: targetPaneId)
            },
            hostViewsProvider: { [weak self] in
                guard let self else { return [] }
                return self.viewRegistry.registeredPaneIds.compactMap { self.viewRegistry.view(for: $0) }
            },
            selectTab: { _ in },
            selectPane: { _, _ in },
            selectDrawerPane: { _, _ in },
            selectEmptyDrawer: { _ in },
            syncRuntimeFocus: { [weak self] surfaceId in
                self?.surfaceManager.syncFocus(activeSurfaceId: surfaceId)
            }
        )
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
            position: position,
            drawerPayloadsByParentPaneId: drawerMovePayloadsByParentPaneId(inTab: sourceTabId)
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
