import Foundation

@MainActor
extension PaneCoordinator {
    static func computeSwitchArrangementTransitions(
        previousVisiblePaneIds: Set<UUID>,
        previouslyMinimizedPaneIds: Set<UUID>,
        newVisiblePaneIds: Set<UUID>
    ) -> PaneCoordinator.SwitchArrangementTransitions {
        let hiddenPaneIds = previousVisiblePaneIds.subtracting(newVisiblePaneIds)
        let revealedPaneIds = newVisiblePaneIds.subtracting(previousVisiblePaneIds)
        let unminimizedPaneIds = previouslyMinimizedPaneIds.intersection(newVisiblePaneIds)
        return SwitchArrangementTransitions(
            hiddenPaneIds: hiddenPaneIds,
            paneIdsToReattach: revealedPaneIds.union(unminimizedPaneIds)
        )
    }

    /// Open a terminal for a worktree. Creates pane + tab + view.
    /// Returns the pane if a new one was created, nil if already open.
    @discardableResult
    func openTerminal(for worktree: Worktree, in repo: Repo) -> Pane? {
        if let existingTab = store.tabs.first(where: { tab in
            tab.paneIds.contains { paneId in
                store.pane(paneId)?.worktreeId == worktree.id
            }
        }) {
            store.setActiveTab(existingTab.id)
            return nil
        }

        return createTerminalTab(for: worktree, in: repo)
    }

    /// Open a new terminal for a worktree, always creating a fresh pane+tab
    /// (never navigates to an existing one).
    @discardableResult
    func openNewTerminal(for worktree: Worktree, in repo: Repo) -> Pane? {
        createTerminalTab(for: worktree, in: repo)
    }

    /// Open a new webview pane in a new tab. Loads about:blank with navigation bar visible.
    @discardableResult
    func openWebview(url: URL = URL(string: "about:blank")!) -> Pane? {
        let state = WebviewState(url: url, showNavigation: true)
        let host = url.host() ?? "New Tab"
        let pane = store.createPane(
            content: .webview(state),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: host), title: host)
        )

        guard createViewForContent(pane: pane) != nil else {
            paneCoordinatorLogger.error("Webview creation failed — rolling back pane \(pane.id)")
            store.removePane(pane.id)
            return nil
        }

        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        paneCoordinatorLogger.info("Opened webview pane \(pane.id)")
        return pane
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// Execute a resolved PaneAction.
    func execute(_ action: PaneAction) {
        paneCoordinatorLogger.debug("Executing: \(String(describing: action))")

        switch action {
        case .selectTab(let tabId):
            store.setActiveTab(tabId)

        case .closeTab(let tabId):
            executeCloseTab(tabId)

        case .breakUpTab(let tabId):
            executeBreakUpTab(tabId)

        case .closePane(let tabId, let paneId):
            executeClosePane(tabId: tabId, paneId: paneId)

        case .extractPaneToTab(let tabId, let paneId):
            _ = store.extractPane(paneId, fromTab: tabId)

        case .focusPane(let tabId, let paneId):
            if let tab = store.tab(tabId), tab.minimizedPaneIds.contains(paneId) {
                store.expandPane(paneId, inTab: tabId)
                reattachForViewSwitch(paneId: paneId)
            }
            store.setActivePane(paneId, inTab: tabId)

        case .insertPane(let source, let targetTabId, let targetPaneId, let direction):
            executeInsertPane(
                source: source,
                targetTabId: targetTabId,
                targetPaneId: targetPaneId,
                direction: direction
            )

        case .resizePane(let tabId, let splitId, let ratio):
            store.resizePane(tabId: tabId, splitId: splitId, ratio: ratio)

        case .equalizePanes(let tabId):
            store.equalizePanes(tabId: tabId)

        case .toggleSplitZoom(let tabId, let paneId):
            store.toggleZoom(paneId: paneId, inTab: tabId)

        case .moveTab(let tabId, let delta):
            store.moveTabByDelta(tabId: tabId, delta: delta)

        case .minimizePane(let tabId, let paneId):
            if store.minimizePane(paneId, inTab: tabId) {
                detachForViewSwitch(paneId: paneId)
            }

        case .expandPane(let tabId, let paneId):
            store.expandPane(paneId, inTab: tabId)
            reattachForViewSwitch(paneId: paneId)

        case .resizePaneByDelta(let tabId, let paneId, let direction, let amount):
            store.resizePaneByDelta(tabId: tabId, paneId: paneId, direction: direction, amount: amount)

        case .mergeTab(let sourceTabId, let targetTabId, let targetPaneId, let direction):
            executeMergeTab(
                sourceTabId: sourceTabId,
                targetTabId: targetTabId,
                targetPaneId: targetPaneId,
                direction: direction
            )

        case .createArrangement(let tabId, let name, let paneIds):
            _ = store.createArrangement(name: name, paneIds: paneIds, inTab: tabId)

        case .removeArrangement(let tabId, let arrangementId):
            store.removeArrangement(arrangementId, inTab: tabId)

        case .switchArrangement(let tabId, let arrangementId):
            guard let tab = store.tab(tabId) else {
                paneCoordinatorLogger.warning("Cannot switch arrangement: tab \(tabId) not found")
                break
            }
            guard let arrangement = tab.arrangements.first(where: { $0.id == arrangementId }) else {
                paneCoordinatorLogger.warning(
                    "Cannot switch arrangement: arrangement \(arrangementId) not found in tab \(tabId)"
                )
                break
            }

            let previousVisiblePaneIds = tab.activeArrangement.visiblePaneIds
            let previouslyMinimizedPaneIds = tab.minimizedPaneIds
            store.switchArrangement(to: arrangementId, inTab: tabId)
            let newVisiblePaneIds = arrangement.visiblePaneIds

            let transitions = Self.computeSwitchArrangementTransitions(
                previousVisiblePaneIds: previousVisiblePaneIds,
                previouslyMinimizedPaneIds: previouslyMinimizedPaneIds,
                newVisiblePaneIds: newVisiblePaneIds
            )

            for paneId in transitions.hiddenPaneIds {
                detachForViewSwitch(paneId: paneId)
            }

            for paneId in transitions.paneIdsToReattach {
                reattachForViewSwitch(paneId: paneId)
            }

        case .renameArrangement(let tabId, let arrangementId, let name):
            store.renameArrangement(arrangementId, name: name, inTab: tabId)

        case .backgroundPane(let paneId):
            store.backgroundPane(paneId)

        case .reactivatePane(let paneId, let targetTabId, let targetPaneId, let direction):
            let layoutDirection = bridgeDirection(direction)
            let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after
            store.reactivatePane(
                paneId,
                inTab: targetTabId,
                at: targetPaneId,
                direction: layoutDirection,
                position: position
            )
            if viewRegistry.view(for: paneId) == nil, let pane = store.pane(paneId) {
                guard createViewForContent(pane: pane) != nil else {
                    paneCoordinatorLogger.error(
                        "reactivatePane: view creation failed for \(paneId) — rolling pane back to background"
                    )
                    store.backgroundPane(paneId)
                    break
                }
            }

        case .purgeOrphanedPane(let paneId):
            guard let pane = store.pane(paneId), pane.residency == .backgrounded else { break }
            teardownView(for: paneId)
            store.purgeOrphanedPane(paneId)

        case .addDrawerPane(let parentPaneId):
            if let drawerPane = store.addDrawerPane(to: parentPaneId) {
                if createViewForContent(pane: drawerPane) == nil {
                    paneCoordinatorLogger.error(
                        "addDrawerPane: view creation failed for \(drawerPane.id) — rolling back drawer pane"
                    )
                    rollbackDrawerPaneCreation(drawerPane.id, from: parentPaneId)
                }
            }

        case .removeDrawerPane(let parentPaneId, let drawerPaneId):
            teardownView(for: drawerPaneId)
            store.removeDrawerPane(drawerPaneId, from: parentPaneId)

        case .toggleDrawer(let paneId):
            store.toggleDrawer(for: paneId)

        case .setActiveDrawerPane(let parentPaneId, let drawerPaneId):
            store.setActiveDrawerPane(drawerPaneId, in: parentPaneId)
            if let terminalView = viewRegistry.terminalView(for: drawerPaneId) {
                terminalView.window?.makeFirstResponder(terminalView)
                surfaceManager.syncFocus(activeSurfaceId: terminalView.surfaceId)
            }

        case .resizeDrawerPane(let parentPaneId, let splitId, let ratio):
            store.resizeDrawerPane(parentPaneId: parentPaneId, splitId: splitId, ratio: ratio)

        case .equalizeDrawerPanes(let parentPaneId):
            store.equalizeDrawerPanes(parentPaneId: parentPaneId)

        case .minimizeDrawerPane(let parentPaneId, let drawerPaneId):
            if store.minimizeDrawerPane(drawerPaneId, in: parentPaneId) {
                detachForViewSwitch(paneId: drawerPaneId)
            }

        case .expandDrawerPane(let parentPaneId, let drawerPaneId):
            store.expandDrawerPane(drawerPaneId, in: parentPaneId)
            reattachForViewSwitch(paneId: drawerPaneId)

        case .insertDrawerPane(let parentPaneId, let targetDrawerPaneId, let direction):
            executeInsertDrawerPane(
                parentPaneId: parentPaneId,
                targetDrawerPaneId: targetDrawerPaneId,
                direction: direction
            )

        case .expireUndoEntry(let paneId):
            paneCoordinatorLogger.warning("expireUndoEntry: \(paneId) — stub, full impl in Phase 3")

        case .repair(let repairAction):
            executeRepair(repairAction)
        }
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    /// Common path: create pane + view + tab for a worktree.
    private func createTerminalTab(for worktree: Worktree, in repo: Repo) -> Pane? {
        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            title: worktree.name,
            provider: .zmx,
            lifetime: .persistent,
            residency: .active
        )

        guard createView(for: pane, worktree: worktree, repo: repo) != nil else {
            paneCoordinatorLogger.error(
                "Surface creation failed for worktree '\(worktree.name)' — rolling back pane \(pane.id)")
            store.removePane(pane.id)
            return nil
        }

        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        paneCoordinatorLogger.info("Opened terminal for worktree: \(worktree.name)")
        return pane
    }

    private func executeCloseTab(_ tabId: UUID) {
        syncWebviewStates()

        if let snapshot = store.snapshotForClose(tabId: tabId) {
            undoStack.append(.tab(snapshot))
        } else {
            paneCoordinatorLogger.warning("closeTab: snapshot failed for tab \(tabId); undo will be unavailable")
        }

        if let tab = store.tab(tabId) {
            for paneId in tab.panes {
                teardownDrawerPanes(for: paneId)
                teardownView(for: paneId)
            }
        }

        store.removeTab(tabId)
        expireOldUndoEntries()
    }

    /// Remove oldest undo entries beyond the limit, cleaning up their orphaned panes.
    private func expireOldUndoEntries() {
        while undoStack.count > maxUndoStackSize {
            let expired = undoStack.removeFirst()

            let allOwnedPaneIds = currentOwnedPaneIds()

            let expiredPanes: [Pane]
            switch expired {
            case .tab(let s): expiredPanes = s.panes
            case .pane(let s): expiredPanes = [s.pane] + s.drawerChildPanes
            }

            for pane in expiredPanes where !allOwnedPaneIds.contains(pane.id) {
                teardownView(for: pane.id)
                store.removePane(pane.id)
                paneCoordinatorLogger.debug("GC'd orphaned pane \(pane.id) from expired undo entry")
            }
        }
    }

    private func currentOwnedPaneIds() -> Set<UUID> {
        Set(
            store.tabs.flatMap { tab in
                tab.panes.flatMap { paneId -> [UUID] in
                    var paneIds = [paneId]
                    if let drawer = store.pane(paneId)?.drawer {
                        paneIds.append(contentsOf: drawer.paneIds)
                    }
                    return paneIds
                }
            }
        )
    }

    private func executeBreakUpTab(_ tabId: UUID) {
        let newTabs = store.breakUpTab(tabId)
        if newTabs.isEmpty {
            paneCoordinatorLogger.debug("breakUpTab: tab has single pane, no-op")
        }
    }

    private func executeClosePane(tabId: UUID, paneId: UUID) {
        guard let closingPane = store.pane(paneId) else {
            paneCoordinatorLogger.warning("closePane: pane \(paneId) not found")
            return
        }

        if !closingPane.isDrawerChild, let tab = store.tab(tabId), tab.paneIds.count <= 1 {
            executeCloseTab(tabId)
            return
        }

        if let snapshot = store.snapshotForPaneClose(paneId: paneId, inTab: tabId) {
            undoStack.append(.pane(snapshot))
        } else {
            paneCoordinatorLogger.warning("closePane: snapshot failed for pane \(paneId) in tab \(tabId)")
        }

        if closingPane.isDrawerChild {
            teardownView(for: paneId)
            if let parentPaneId = closingPane.parentPaneId {
                store.removeDrawerPane(paneId, from: parentPaneId)
            } else {
                store.removePane(paneId)
            }
            expireOldUndoEntries()
            return
        }

        let drawerChildIds = closingPane.drawer?.paneIds ?? []
        teardownDrawerPanes(for: paneId)
        teardownView(for: paneId)
        let tabNowEmpty = store.removePaneFromLayout(paneId, inTab: tabId)

        if tabNowEmpty {
            executeCloseTab(tabId)
            return
        }

        for drawerPaneId in drawerChildIds {
            store.removeDrawerPane(drawerPaneId, from: paneId)
        }

        let allOwnedPaneIds = currentOwnedPaneIds()
        if !allOwnedPaneIds.contains(paneId) {
            store.removePane(paneId)
        }

        expireOldUndoEntries()
    }

    private func executeInsertPane(
        source: PaneSource,
        targetTabId: UUID,
        targetPaneId: UUID,
        direction: SplitNewDirection
    ) {
        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after

        switch source {
        case .existingPane(let paneId, let sourceTabId):
            let sourceTabEmpty = store.removePaneFromLayout(paneId, inTab: sourceTabId)
            store.insertPane(
                paneId, inTab: targetTabId, at: targetPaneId,
                direction: layoutDirection, position: position
            )
            if sourceTabEmpty {
                store.removeTab(sourceTabId)
            }

        case .newTerminal:
            let targetPane = store.pane(targetPaneId)
            guard let worktreeId = targetPane?.worktreeId,
                let repoId = targetPane?.repoId,
                let worktree = store.worktree(worktreeId),
                let repo = store.repo(repoId)
            else {
                paneCoordinatorLogger.warning(
                    "Cannot insert new terminal pane — target pane has no worktree/repo context")
                return
            }

            let pane = store.createPane(
                source: .worktree(worktreeId: worktreeId, repoId: repoId),
                provider: .zmx
            )

            guard createView(for: pane, worktree: worktree, repo: repo) != nil else {
                paneCoordinatorLogger.error("Surface creation failed for new pane — rolling back pane \(pane.id)")
                store.removePane(pane.id)
                return
            }

            store.insertPane(
                pane.id, inTab: targetTabId, at: targetPaneId,
                direction: layoutDirection, position: position
            )
        }
    }

    private func executeInsertDrawerPane(
        parentPaneId: UUID,
        targetDrawerPaneId: UUID,
        direction: SplitNewDirection
    ) {
        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after

        guard
            let drawerPane = store.insertDrawerPane(
                in: parentPaneId,
                at: targetDrawerPaneId,
                direction: layoutDirection,
                position: position
            )
        else { return }

        if createViewForContent(pane: drawerPane) == nil {
            paneCoordinatorLogger.error(
                "insertDrawerPane: view creation failed for \(drawerPane.id) — rolling back drawer pane"
            )
            rollbackDrawerPaneCreation(drawerPane.id, from: parentPaneId)
        }
    }

    private func executeMergeTab(
        sourceTabId: UUID,
        targetTabId: UUID,
        targetPaneId: UUID,
        direction: SplitNewDirection
    ) {
        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after

        store.mergeTab(
            sourceId: sourceTabId,
            intoTarget: targetTabId,
            at: targetPaneId,
            direction: layoutDirection,
            position: position
        )
    }

    private func executeRepair(_ repairAction: RepairAction) {
        switch repairAction {
        case .recreateSurface(let paneId):
            guard let pane = store.pane(paneId) else {
                paneCoordinatorLogger.warning("repair \(String(describing: repairAction)): pane not in store")
                return
            }
            teardownView(for: paneId, unregisterRuntime: false)
            guard createViewForContent(pane: pane) != nil else {
                paneCoordinatorLogger.error("repair recreateSurface failed for pane \(paneId)")
                return
            }
            store.bumpViewRevision()
            paneCoordinatorLogger.info("Repaired view for pane \(paneId)")

        case .createMissingView(let paneId):
            guard let pane = store.pane(paneId) else {
                paneCoordinatorLogger.warning("repair \(String(describing: repairAction)): pane not in store")
                return
            }
            guard viewRegistry.view(for: paneId) == nil else {
                paneCoordinatorLogger.info("repair createMissingView: pane \(paneId) already has a view")
                return
            }
            guard createViewForContent(pane: pane) != nil else {
                paneCoordinatorLogger.error("repair createMissingView failed for pane \(paneId)")
                return
            }
            store.bumpViewRevision()
            paneCoordinatorLogger.info("Created missing view for pane \(paneId)")

        case .reattachZmx, .markSessionFailed, .cleanupOrphan:
            paneCoordinatorLogger.warning("repair: \(String(describing: repairAction)) — not yet implemented")
        }
    }

    private func rollbackDrawerPaneCreation(_ drawerPaneId: UUID, from parentPaneId: UUID) {
        teardownView(for: drawerPaneId)
        store.removeDrawerPane(drawerPaneId, from: parentPaneId)
    }

    /// Teardown views for all drawer panes owned by a parent pane.
    private func teardownDrawerPanes(for parentPaneId: UUID) {
        guard let pane = store.pane(parentPaneId),
            let drawer = pane.drawer
        else { return }
        for drawerPaneId in drawer.paneIds {
            teardownView(for: drawerPaneId)
        }
    }

    /// Bridge SplitNewDirection → Layout.SplitDirection.
    private func bridgeDirection(_ direction: SplitNewDirection) -> Layout.SplitDirection {
        switch direction {
        case .left, .right: return .horizontal
        case .up, .down: return .vertical
        }
    }
}
