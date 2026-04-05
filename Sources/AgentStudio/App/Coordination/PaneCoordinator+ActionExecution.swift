import AppKit
import Foundation

@MainActor
extension PaneCoordinator {
    private static var nextWorkspaceActivitySeq: UInt64 = 0
    private static let defaultGitHubURL = URL(string: "https://github.com")!

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
            postRecentTargetOpened(
                target: .forWorktree(
                    path: worktree.path,
                    worktree: worktree,
                    repo: repo
                )
            )
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

    /// Open a worktree terminal as a split pane in the active tab.
    /// Falls back to opening a new tab when there is no active split target.
    @discardableResult
    func openWorktreeInPane(for worktree: Worktree, in repo: Repo) -> Pane? {
        guard
            let activeTabId = store.activeTabId,
            let activeTab = store.tab(activeTabId),
            let targetPaneId = activeTab.activePaneId
        else {
            return openNewTerminal(for: worktree, in: repo)
        }

        let pane = store.createPane(
            source: .worktree(
                worktreeId: worktree.id,
                repoId: repo.id,
                launchDirectory: worktree.path
            ),
            title: worktree.name,
            provider: .zmx,
            lifetime: .persistent,
            residency: .active
        )
        viewRegistry.ensureSlot(for: pane.id)

        store.insertPane(
            pane.id,
            inTab: activeTabId,
            at: targetPaneId,
            direction: .horizontal,
            position: .after
        )
        store.setActivePane(pane.id, inTab: activeTabId)
        ensureTerminalPaneView(pane)
        postRecentTargetOpened(
            target: .forWorktree(
                path: worktree.path,
                worktree: worktree,
                repo: repo
            )
        )

        Self.logger.info("Opened worktree '\(worktree.name)' in split pane")
        return pane
    }

    /// Open a new generic GitHub webview pane in a new tab.
    @discardableResult
    func openWebview(url: URL = defaultGitHubURL) -> Pane? {
        let state = WebviewState(url: url, showNavigation: true)
        let host = url.host() ?? "New Tab"
        let pane = store.createPane(
            content: .webview(state),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: host), title: host)
        )
        viewRegistry.ensureSlot(for: pane.id)

        guard createViewForContent(pane: pane) != nil else {
            Self.logger.error("Webview creation failed — rolling back pane \(pane.id)")
            store.removePane(pane.id)
            viewRegistry.removeSlot(for: pane.id)
            return nil
        }

        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        Self.logger.info("Opened webview pane \(pane.id)")
        return pane
    }

    @discardableResult
    func openContextualWebviewInPane(
        sourcePaneId: UUID,
        targetTabId: UUID,
        url: URL,
        direction: SplitNewDirection = .right
    ) -> Pane? {
        guard let targetPane = store.pane(sourcePaneId) else {
            Self.logger.warning("openContextualWebviewInPane: source pane \(sourcePaneId) not found")
            return nil
        }
        guard store.tab(targetTabId) != nil else {
            Self.logger.warning("openContextualWebviewInPane: target tab \(targetTabId) not found")
            return nil
        }

        let host = url.host() ?? "GitHub"
        let context = contextualBrowserMetadata(from: targetPane, fallbackTitle: host)
        let pane = store.createPane(
            content: .webview(WebviewState(url: url, title: host, showNavigation: true)),
            metadata: context.metadata
        )
        viewRegistry.ensureSlot(for: pane.id)

        guard createViewForContent(pane: pane) != nil else {
            Self.logger.error("Contextual webview creation failed — rolling back pane \(pane.id)")
            store.removePane(pane.id)
            viewRegistry.removeSlot(for: pane.id)
            return nil
        }

        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after
        store.insertPane(
            pane.id,
            inTab: targetTabId,
            at: sourcePaneId,
            direction: layoutDirection,
            position: position
        )
        store.setActivePane(pane.id, inTab: targetTabId)

        Self.logger.info("Opened contextual webview pane \(pane.id) from source pane \(sourcePaneId)")
        return pane
    }

    @discardableResult
    func openFloatingTerminal(launchDirectory: URL?, title: String?) -> Pane? {
        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pane = store.createPane(
            source: .floating(launchDirectory: launchDirectory, title: resolvedTitle),
            title: (resolvedTitle?.isEmpty == false) ? resolvedTitle! : "Terminal",
            provider: .zmx,
            facets: PaneContextFacets(cwd: launchDirectory)
        )
        viewRegistry.ensureSlot(for: pane.id)

        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        ensureTerminalPaneView(pane)
        if let launchDirectory {
            postRecentTargetOpened(
                target: .forCwd(
                    launchDirectory,
                    title: resolvedTitle,
                    subtitle: launchDirectory.path
                )
            )
        }

        Self.logger.info("Opened floating terminal pane \(pane.id)")
        return pane
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// Execute a resolved PaneActionCommand.
    func execute(_ action: PaneActionCommand) {
        Self.logger.debug("Executing: \(String(describing: action))")

        switch action {
        case .openWorktree(let worktreeId):
            guard let worktree = store.worktree(worktreeId), let repo = store.repo(containing: worktreeId) else {
                Self.logger.warning("openWorktree: worktree \(worktreeId) not found")
                return
            }
            _ = openTerminal(for: worktree, in: repo)

        case .openNewTerminalInTab(let worktreeId, let launchDirectory, let title):
            guard let worktree = store.worktree(worktreeId), let repo = store.repo(containing: worktreeId) else {
                Self.logger.warning("openNewTerminalInTab: worktree \(worktreeId) not found")
                return
            }
            _ = createTerminalTab(for: worktree, in: repo, cwdOverride: launchDirectory, titleOverride: title)

        case .openWorktreeInPane(let worktreeId):
            guard let worktree = store.worktree(worktreeId), let repo = store.repo(containing: worktreeId) else {
                Self.logger.warning("openWorktreeInPane: worktree \(worktreeId) not found")
                return
            }
            _ = openWorktreeInPane(for: worktree, in: repo)

        case .openFloatingTerminal(let launchDirectory, let title):
            _ = openFloatingTerminal(launchDirectory: launchDirectory, title: title)

        case .removeRepo(let repoId):
            removeRepoHandler(repoId)

        case .selectTab(let tabId):
            store.setActiveTab(tabId)
            restoreViewsForActiveTabIfNeeded(forceWhenBoundsExist: true)

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
                restoreViewsForActiveTabIfNeeded()
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
            restoreViewsForActiveTabIfNeeded()
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
            if store.createArrangement(name: name, paneIds: paneIds, inTab: tabId) == nil {
                Self.logger.warning(
                    "createArrangement: failed to create arrangement '\(name)' in tab \(tabId)")
            }

        case .removeArrangement(let tabId, let arrangementId):
            store.removeArrangement(arrangementId, inTab: tabId)

        case .switchArrangement(let tabId, let arrangementId):
            guard let tab = store.tab(tabId) else {
                Self.logger.warning("Cannot switch arrangement: tab \(tabId) not found")
                break
            }
            guard let arrangement = tab.arrangements.first(where: { $0.id == arrangementId }) else {
                Self.logger.warning(
                    "Cannot switch arrangement: arrangement \(arrangementId) not found in tab \(tabId)"
                )
                break
            }

            // Capture visibility/minimized state before mutating the active arrangement.
            // Transition calculations depend on before/after sets.
            let previousVisiblePaneIds = tab.activeArrangement.visiblePaneIds
            let previouslyMinimizedPaneIds = tab.minimizedPaneIds
            store.switchArrangement(to: arrangementId, inTab: tabId)
            // Use the resolved arrangement snapshot as the post-switch target state.
            let newVisiblePaneIds = arrangement.visiblePaneIds

            let transitions = Self.computeSwitchArrangementTransitions(
                previousVisiblePaneIds: previousVisiblePaneIds,
                previouslyMinimizedPaneIds: previouslyMinimizedPaneIds,
                newVisiblePaneIds: newVisiblePaneIds
            )

            // Detach hidden panes before reattaching newly visible panes to avoid
            // transient duplicate attachments and focus churn.
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
            viewRegistry.ensureSlot(for: paneId)
            if viewRegistry.view(for: paneId) == nil, let pane = store.pane(paneId) {
                ensureTerminalPaneView(pane)
            }

        case .purgeOrphanedPane(let paneId):
            guard let pane = store.pane(paneId), pane.residency == .backgrounded else { break }
            teardownView(for: paneId)
            store.purgeOrphanedPane(paneId)
            viewRegistry.removeSlot(for: paneId)

        case .addDrawerPane(let parentPaneId):
            if let drawerPane = store.addDrawerPane(to: parentPaneId) {
                viewRegistry.ensureSlot(for: drawerPane.id)
                ensureTerminalPaneView(drawerPane)
            }

        case .removeDrawerPane(let parentPaneId, let drawerPaneId):
            teardownView(for: drawerPaneId)
            store.removeDrawerPane(drawerPaneId, from: parentPaneId)
            viewRegistry.removeSlot(for: drawerPaneId)

        case .toggleDrawer(let paneId):
            store.toggleDrawer(for: paneId)

        case .setActiveDrawerPane(let parentPaneId, let drawerPaneId):
            store.setActiveDrawerPane(drawerPaneId, in: parentPaneId)
            restoreViewsForActiveTabIfNeeded()
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
            restoreViewsForActiveTabIfNeeded()
            reattachForViewSwitch(paneId: drawerPaneId)

        case .insertDrawerPane(let parentPaneId, let targetDrawerPaneId, let direction):
            executeInsertDrawerPane(
                parentPaneId: parentPaneId,
                targetDrawerPaneId: targetDrawerPaneId,
                direction: direction
            )

        case .moveDrawerPane(let parentPaneId, let drawerPaneId, let targetDrawerPaneId, let direction):
            let layoutDirection = bridgeDirection(direction)
            let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after
            store.moveDrawerPane(
                drawerPaneId,
                in: parentPaneId,
                at: targetDrawerPaneId,
                direction: layoutDirection,
                position: position
            )
            if let terminalView = viewRegistry.terminalView(for: drawerPaneId) {
                terminalView.window?.makeFirstResponder(terminalView)
                surfaceManager.syncFocus(activeSurfaceId: terminalView.surfaceId)
            }

        case .duplicatePane(let tabId, let paneId, _):
            Self.logger.info(
                "duplicatePane: pane \(paneId) in tab \(tabId) — not yet implemented"
            )

        case .expireUndoEntry:
            Self.logger.warning(
                "expireUndoEntry: explicit per-pane expiry is currently unsupported; undo GC is handled by expireOldUndoEntries()"
            )

        case .repair(let repairAction):
            executeRepair(repairAction)
        }

        syncFilesystemRootsAndActivity()
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    /// Common path: create pane + view + tab for a worktree.
    private func createTerminalTab(
        for worktree: Worktree,
        in repo: Repo,
        cwdOverride: URL? = nil,
        titleOverride: String? = nil
    ) -> Pane? {
        let resolvedCwd = cwdOverride ?? worktree.path
        let resolvedTitle = titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let paneFacets = PaneContextFacets(
            repoId: repo.id,
            repoName: repo.name,
            worktreeId: worktree.id,
            worktreeName: worktree.name,
            cwd: resolvedCwd,
            parentFolder: repo.repoPath.deletingLastPathComponent().path
        )
        let pane = store.createPane(
            source: .worktree(
                worktreeId: worktree.id,
                repoId: repo.id,
                launchDirectory: resolvedCwd
            ),
            title: (resolvedTitle?.isEmpty == false) ? resolvedTitle! : worktree.name,
            provider: .zmx,
            lifetime: .persistent,
            residency: .active,
            facets: paneFacets
        )
        viewRegistry.ensureSlot(for: pane.id)

        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        ensureTerminalPaneView(pane)
        postRecentTargetOpened(
            target: .forWorktree(
                path: resolvedCwd,
                worktree: worktree,
                repo: repo,
                displayTitle: resolvedTitle,
                subtitle: repo.name
            )
        )

        Self.logger.info("Opened terminal for worktree: \(worktree.name)")
        return pane
    }

    private func postRecentTargetOpened(target: RecentWorkspaceTarget) {
        Self.nextWorkspaceActivitySeq += 1
        let envelope = RuntimeEnvelope.system(
            SystemEnvelope(
                source: .builtin(.coordinator),
                seq: Self.nextWorkspaceActivitySeq,
                timestamp: .now,
                event: .workspaceActivity(.recentTargetOpened(target))
            )
        )

        Task {
            guard !Task.isCancelled else { return }
            await PaneRuntimeEventBus.shared.post(envelope)
            Self.logger.debug("Posted recent target event id=\(target.id, privacy: .public)")
        }
    }

    private func executeCloseTab(_ tabId: UUID) {
        syncWebviewStates()

        if let snapshot = store.snapshotForClose(tabId: tabId) {
            appendUndoEntry(.tab(snapshot))
        } else {
            Self.logger.warning("closeTab: snapshot failed for tab \(tabId); undo will be unavailable")
        }

        if let tab = store.tab(tabId) {
            // Close-tab keeps pane models alive for undo snapshots, so teardown only
            // unregisters hosts. Slots are intentionally preserved until the panes
            // are permanently purged from the store.
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
            let expired = removeFirstUndoEntry()

            let allOwnedPaneIds = currentOwnedPaneIds()

            let expiredPanes: [Pane]
            switch expired {
            case .tab(let s): expiredPanes = s.panes
            case .pane(let s): expiredPanes = [s.pane] + s.drawerChildPanes
            }

            for pane in expiredPanes where !allOwnedPaneIds.contains(pane.id) {
                teardownView(for: pane.id)
                store.removePane(pane.id)
                viewRegistry.removeSlot(for: pane.id)
                Self.logger.debug("GC'd orphaned pane \(pane.id) from expired undo entry")
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
            Self.logger.debug("breakUpTab: tab has single pane, no-op")
        }
    }

    private func executeClosePane(tabId: UUID, paneId: UUID) {
        guard let closingPane = store.pane(paneId) else {
            Self.logger.warning("closePane: pane \(paneId) not found")
            return
        }

        let shouldCreateUndoEntry: Bool
        if let tab = store.tab(tabId), tab.id == store.activeTabId {
            if closingPane.isDrawerChild {
                shouldCreateUndoEntry = closingPane.parentPaneId.map { tab.paneIds.contains($0) } ?? false
            } else {
                shouldCreateUndoEntry = tab.paneIds.contains(paneId)
            }
        } else {
            shouldCreateUndoEntry = false
        }

        if shouldCreateUndoEntry {
            if let snapshot = store.snapshotForPaneClose(paneId: paneId, inTab: tabId) {
                appendUndoEntry(.pane(snapshot))
            } else {
                Self.logger.warning("closePane: snapshot failed for pane \(paneId) in tab \(tabId)")
            }
        } else {
            Self.logger.debug("closePane: skipping undo snapshot for non-visible pane \(paneId) in tab \(tabId)")
        }

        if closingPane.isDrawerChild {
            teardownView(for: paneId)
            if let parentPaneId = closingPane.parentPaneId {
                store.removeDrawerPane(paneId, from: parentPaneId)
                viewRegistry.removeSlot(for: paneId)
            } else {
                store.removePane(paneId)
                viewRegistry.removeSlot(for: paneId)
            }
            expireOldUndoEntries()
            return
        }

        let drawerChildIds = closingPane.drawer?.paneIds ?? []
        teardownDrawerPanes(for: paneId)
        teardownView(for: paneId)
        store.removePaneFromLayout(paneId, inTab: tabId)

        for drawerPaneId in drawerChildIds {
            store.removeDrawerPane(drawerPaneId, from: paneId)
            viewRegistry.removeSlot(for: drawerPaneId)
        }

        let allOwnedPaneIds = currentOwnedPaneIds()
        if !allOwnedPaneIds.contains(paneId) {
            store.removePane(paneId)
            viewRegistry.removeSlot(for: paneId)
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
            guard store.pane(paneId) != nil else {
                Self.logger.warning("insertPane existingPane: pane \(paneId) not found")
                return
            }
            guard store.tab(sourceTabId) != nil else {
                Self.logger.warning("insertPane existingPane: source tab \(sourceTabId) not found")
                return
            }
            guard store.tab(targetTabId) != nil else {
                Self.logger.warning("insertPane existingPane: target tab \(targetTabId) not found")
                return
            }
            store.removePaneFromLayout(paneId, inTab: sourceTabId)
            store.insertPane(
                paneId, inTab: targetTabId, at: targetPaneId,
                direction: layoutDirection, position: position
            )

        case .newTerminal:
            let targetPane = store.pane(targetPaneId)
            if let resolved = resolvedWorktreeContext(for: targetPane) {
                let pane = store.createPane(
                    source: .worktree(
                        worktreeId: resolved.worktree.id,
                        repoId: resolved.repo.id,
                        launchDirectory: targetPane?.metadata.cwd ?? targetPane?.metadata.launchDirectory
                            ?? resolved.worktree.path
                    ),
                    provider: .zmx,
                    facets: targetPane?.metadata.facets ?? .empty
                )
                viewRegistry.ensureSlot(for: pane.id)

                store.insertPane(
                    pane.id, inTab: targetTabId, at: targetPaneId,
                    direction: layoutDirection, position: position
                )
                ensureTerminalPaneView(pane)
                return
            }

            let pane = store.createPane(
                source: .floating(
                    launchDirectory: targetPane?.metadata.cwd ?? targetPane?.metadata.launchDirectory,
                    title: nil
                ),
                provider: .zmx,
                facets: targetPane?.metadata.facets ?? .empty
            )
            viewRegistry.ensureSlot(for: pane.id)

            store.insertPane(
                pane.id, inTab: targetTabId, at: targetPaneId,
                direction: layoutDirection, position: position
            )
            ensureTerminalPaneView(pane)
        }
    }

    private func resolvedWorktreeContext(
        for targetPane: Pane?
    ) -> (repo: Repo, worktree: Worktree)? {
        if let worktreeId = targetPane?.worktreeId,
            let repoId = targetPane?.repoId,
            let worktree = store.worktree(worktreeId),
            let repo = store.repo(repoId)
        {
            return (repo, worktree)
        }

        return store.repoAndWorktree(containing: targetPane?.metadata.facets.cwd)
    }

    private func contextualBrowserMetadata(
        from pane: Pane,
        fallbackTitle: String
    ) -> (
        metadata: PaneMetadata,
        repo: Repo?,
        worktree: Worktree?
    ) {
        if let worktreeId = pane.worktreeId,
            let repoId = pane.repoId,
            let repo = store.repo(repoId),
            let worktree = store.worktree(worktreeId)
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

        if let resolved = store.repoAndWorktree(containing: pane.metadata.cwd) {
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
        else {
            Self.logger.warning(
                "insertDrawerPane: failed to insert drawer pane under parent \(parentPaneId) at target \(targetDrawerPaneId)"
            )
            return
        }

        viewRegistry.ensureSlot(for: drawerPane.id)
        ensureTerminalPaneView(drawerPane)
    }

    private func ensureTerminalPaneView(_ pane: Pane) {
        registerTerminalPlaceholderIfNeeded(for: pane, mode: .preparing)
        if createViewForContentUsingCurrentGeometry(pane: pane) == nil {
            RestoreTrace.log("ensureTerminalPaneView deferred pane=\(pane.id)")
            restoreViewsForActiveTabIfNeeded()
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
            guard let pane = store.pane(paneId) else {
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
    private func createViewForRepair(for pane: Pane) -> NSView? {
        if case .terminal = pane.content {
            return createViewForContentUsingCurrentGeometry(pane: pane)
        }
        return createViewForContent(pane: pane)
    }

    /// Teardown views for all drawer panes owned by a parent pane.
    func teardownDrawerPanes(for parentPaneId: UUID) {
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
