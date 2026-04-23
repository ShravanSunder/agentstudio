import AppKit

@MainActor
extension PaneCoordinator {
    private static var nextWorkspaceActivitySeq: UInt64 = 0
    private static let defaultGitHubURL = URL(string: "https://github.com")!

    static func computeSwitchArrangementTransitions(
        previousVisiblePaneIds: Set<UUID>,
        previouslyMinimizedPaneIds: Set<UUID>,
        newVisiblePaneIds: Set<UUID>,
        newMinimizedPaneIds: Set<UUID>
    ) -> PaneCoordinator.SwitchArrangementTransitions {
        let previouslyPresentedPaneIds = previousVisiblePaneIds.subtracting(previouslyMinimizedPaneIds)
        let newlyPresentedPaneIds = newVisiblePaneIds.subtracting(newMinimizedPaneIds)
        let hiddenPaneIds = previouslyPresentedPaneIds.subtracting(newlyPresentedPaneIds)
        let revealedPaneIds = newlyPresentedPaneIds.subtracting(previouslyPresentedPaneIds)
        return SwitchArrangementTransitions(
            hiddenPaneIds: hiddenPaneIds,
            paneIdsToReattach: revealedPaneIds
        )
    }

    /// Open a terminal for a worktree. Creates pane + tab + view.
    /// Returns the pane if a new one was created, nil if already open.
    @discardableResult
    func openTerminal(for worktree: Worktree, in repo: Repo) -> Pane? {
        if let existingTab = store.tabLayoutAtom.tabs.first(where: { tab in
            tab.allPaneIds.contains { paneId in
                store.paneAtom.pane(paneId)?.worktreeId == worktree.id
            }
        }) {
            store.tabLayoutAtom.setActiveTab(existingTab.id)
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
            let activeTabId = store.tabLayoutAtom.activeTabId,
            let activeTab = store.tabLayoutAtom.tab(activeTabId),
            let targetPaneId = activeTab.activePaneId
        else {
            return openNewTerminal(for: worktree, in: repo)
        }

        let pane = store.paneAtom.createPane(
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

        store.tabLayoutAtom.insertPane(
            pane.id,
            inTab: activeTabId,
            at: targetPaneId,
            direction: .horizontal,
            position: .after
        )
        store.tabLayoutAtom.setActivePane(pane.id, inTab: activeTabId)
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
        let pane = store.paneAtom.createPane(
            content: .webview(state),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: host), title: host)
        )
        viewRegistry.ensureSlot(for: pane.id)

        guard createViewForContent(pane: pane) != nil else {
            Self.logger.error("Webview creation failed — rolling back pane \(pane.id)")
            store.mutationCoordinator.removePane(pane.id)
            viewRegistry.removeSlot(for: pane.id)
            return nil
        }

        let tab = Tab(paneId: pane.id, name: tabNameForPane(pane))
        store.tabLayoutAtom.appendTab(tab)
        store.tabLayoutAtom.setActiveTab(tab.id)

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
        guard let targetPane = store.paneAtom.pane(sourcePaneId) else {
            Self.logger.warning("openContextualWebviewInPane: source pane \(sourcePaneId) not found")
            return nil
        }
        guard store.tabLayoutAtom.tab(targetTabId) != nil else {
            Self.logger.warning("openContextualWebviewInPane: target tab \(targetTabId) not found")
            return nil
        }

        let host = url.host() ?? "GitHub"
        let context = contextualBrowserMetadata(from: targetPane, fallbackTitle: host)
        let pane = store.paneAtom.createPane(
            content: .webview(WebviewState(url: url, title: host, showNavigation: true)),
            metadata: context.metadata
        )
        viewRegistry.ensureSlot(for: pane.id)

        guard createViewForContent(pane: pane) != nil else {
            Self.logger.error("Contextual webview creation failed — rolling back pane \(pane.id)")
            store.mutationCoordinator.removePane(pane.id)
            viewRegistry.removeSlot(for: pane.id)
            return nil
        }

        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after
        store.tabLayoutAtom.insertPane(
            pane.id,
            inTab: targetTabId,
            at: sourcePaneId,
            direction: layoutDirection,
            position: position
        )
        store.tabLayoutAtom.setActivePane(pane.id, inTab: targetTabId)

        Self.logger.info("Opened contextual webview pane \(pane.id) from source pane \(sourcePaneId)")
        return pane
    }

    @discardableResult
    func openContextualWebviewInDrawer(
        parentPaneId: UUID,
        url: URL
    ) -> Pane? {
        guard let parentPane = store.paneAtom.pane(parentPaneId) else {
            Self.logger.warning("openContextualWebviewInDrawer: parent pane \(parentPaneId) not found")
            return nil
        }

        let host = url.host() ?? "GitHub"
        let context = contextualBrowserMetadata(from: parentPane, fallbackTitle: host)
        guard
            let pane = store.paneAtom.addDrawerPane(
                to: parentPaneId,
                content: .webview(WebviewState(url: url, title: host, showNavigation: true)),
                metadata: context.metadata
            )
        else {
            Self.logger.warning("openContextualWebviewInDrawer: failed to create drawer pane for \(parentPaneId)")
            return nil
        }

        viewRegistry.ensureSlot(for: pane.id)
        guard createViewForContent(pane: pane) != nil else {
            Self.logger.error("Contextual drawer webview creation failed — rolling back pane \(pane.id)")
            store.paneAtom.removeDrawerPane(pane.id, from: parentPaneId)
            viewRegistry.removeSlot(for: pane.id)
            return nil
        }

        focusVisiblePaneHost(pane.id)
        Self.logger.info("Opened contextual drawer webview pane \(pane.id) from parent pane \(parentPaneId)")
        return pane
    }

    @discardableResult
    func openFloatingTerminal(launchDirectory: URL?, title: String?) -> Pane? {
        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pane = store.paneAtom.createPane(
            source: .floating(launchDirectory: launchDirectory, title: resolvedTitle),
            title: (resolvedTitle?.isEmpty == false) ? resolvedTitle! : "Terminal",
            provider: .zmx,
            facets: PaneContextFacets(cwd: launchDirectory)
        )
        viewRegistry.ensureSlot(for: pane.id)

        let tab = Tab(paneId: pane.id, name: tabNameForPane(pane))
        store.tabLayoutAtom.appendTab(tab)
        store.tabLayoutAtom.setActiveTab(tab.id)
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
            guard
                let worktree = store.repositoryTopologyAtom.worktree(worktreeId),
                let repo = store.repositoryTopologyAtom.repo(containing: worktreeId)
            else {
                Self.logger.warning("openWorktree: worktree \(worktreeId) not found")
                return
            }
            _ = openTerminal(for: worktree, in: repo)

        case .openNewTerminalInTab(let worktreeId, let launchDirectory, let title):
            guard
                let worktree = store.repositoryTopologyAtom.worktree(worktreeId),
                let repo = store.repositoryTopologyAtom.repo(containing: worktreeId)
            else {
                Self.logger.warning("openNewTerminalInTab: worktree \(worktreeId) not found")
                return
            }
            _ = createTerminalTab(for: worktree, in: repo, cwdOverride: launchDirectory, titleOverride: title)

        case .openWorktreeInPane(let worktreeId):
            guard
                let worktree = store.repositoryTopologyAtom.worktree(worktreeId),
                let repo = store.repositoryTopologyAtom.repo(containing: worktreeId)
            else {
                Self.logger.warning("openWorktreeInPane: worktree \(worktreeId) not found")
                return
            }
            _ = openWorktreeInPane(for: worktree, in: repo)

        case .openFloatingTerminal(let launchDirectory, let title):
            _ = openFloatingTerminal(launchDirectory: launchDirectory, title: title)

        case .removeRepo(let repoId):
            removeRepoHandler(repoId)

        case .selectTab(let tabId):
            store.tabLayoutAtom.setActiveTab(tabId)
            restoreViewsForActiveTabIfNeeded(forceWhenBoundsExist: true)

        case .closeTab(let tabId):
            executeCloseTab(tabId)

        case .breakUpTab(let tabId):
            executeBreakUpTab(tabId)

        case .renameTab(let tabId, let name):
            store.tabLayoutAtom.renameTab(tabId, name: name)

        case .closePane(let tabId, let paneId):
            executeClosePane(tabId: tabId, paneId: paneId)

        case .extractPaneToTab(let tabId, let paneId):
            guard let newTab = store.tabLayoutAtom.extractPane(paneId, fromTab: tabId) else {
                break
            }
            guard let pane = store.paneAtom.pane(paneId) else {
                Self.logger.warning("extractPaneToTab: extracted pane \(paneId) missing after tab extraction")
                break
            }
            store.tabLayoutAtom.renameTab(newTab.id, name: tabNameForPane(pane))

        case .scrollToBottom(_, let paneId):
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await self.dispatchRuntimeCommand(
                    .terminal(.scrollToBottom),
                    target: .pane(PaneId(uuid: paneId))
                )
            }

        case .insertPaneRequest(let request):
            executeInsertPane(
                source: request.source,
                targetTabId: request.targetTabId,
                targetPaneId: request.targetPaneId,
                direction: request.direction,
                sizingMode: request.sizingMode
            )

        case .resizePane(let tabId, let splitId, let ratio):
            store.tabLayoutAtom.resizePane(tabId: tabId, splitId: splitId, ratio: ratio)

        case .equalizePanes(let tabId):
            store.tabLayoutAtom.equalizePanes(tabId: tabId)

        case .toggleSplitZoom(let tabId, let paneId):
            store.tabLayoutAtom.toggleZoom(paneId: paneId, inTab: tabId)

        case .moveTab(let tabId, let delta):
            store.tabLayoutAtom.moveTabByDelta(tabId: tabId, delta: delta)

        case .minimizePane(let tabId, let paneId):
            if store.tabLayoutAtom.minimizePane(paneId, inTab: tabId) {
                detachForViewSwitch(paneId: paneId)
            }

        case .expandPane(let tabId, let paneId):
            store.tabLayoutAtom.expandPane(paneId, inTab: tabId)
            restoreVisiblePaneIfNeeded(paneId, forceWhenBoundsExist: true)
            if viewRegistry.terminalView(for: paneId) != nil {
                reattachForViewSwitch(paneId: paneId)
            }

        case .resizePaneByDelta(let tabId, let paneId, let direction, let amount):
            store.tabLayoutAtom.resizePaneByDelta(tabId: tabId, paneId: paneId, direction: direction, amount: amount)

        case .mergeTab(let sourceTabId, let targetTabId, let targetPaneId, let direction):
            executeMergeTab(
                sourceTabId: sourceTabId,
                targetTabId: targetTabId,
                targetPaneId: targetPaneId,
                direction: direction
            )

        case .createArrangement(let tabId, let name, let paneIds):
            if store.tabLayoutAtom.createArrangement(name: name, paneIds: paneIds, inTab: tabId) == nil {
                Self.logger.warning(
                    "createArrangement: failed to create arrangement '\(name)' in tab \(tabId)")
            }

        case .removeArrangement(let tabId, let arrangementId):
            store.tabLayoutAtom.removeArrangement(arrangementId, inTab: tabId)

        case .switchArrangement(let tabId, let arrangementId):
            guard let tab = store.tabLayoutAtom.tab(tabId) else {
                Self.logger.warning("Cannot switch arrangement: tab \(tabId) not found")
                break
            }
            guard tab.arrangements.contains(where: { $0.id == arrangementId }) else {
                Self.logger.warning(
                    "Cannot switch arrangement: arrangement \(arrangementId) not found in tab \(tabId)"
                )
                break
            }

            // Capture visibility/minimized state before mutating the active arrangement.
            // Transition calculations depend on before/after sets.
            let previousVisiblePaneIds = tab.activeArrangement.visiblePaneIds
            let previouslyMinimizedPaneIds = tab.activeMinimizedPaneIds
            store.tabLayoutAtom.switchArrangement(to: arrangementId, inTab: tabId)
            guard let updatedTab = store.tabLayoutAtom.tab(tabId) else {
                Self.logger.warning("Cannot switch arrangement: tab \(tabId) missing after switch")
                break
            }
            let newVisiblePaneIds = updatedTab.activeArrangement.visiblePaneIds
            let newMinimizedPaneIds = updatedTab.activeMinimizedPaneIds

            let transitions = Self.computeSwitchArrangementTransitions(
                previousVisiblePaneIds: previousVisiblePaneIds,
                previouslyMinimizedPaneIds: previouslyMinimizedPaneIds,
                newVisiblePaneIds: newVisiblePaneIds,
                newMinimizedPaneIds: newMinimizedPaneIds
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
            store.tabLayoutAtom.renameArrangement(arrangementId, name: name, inTab: tabId)

        case .backgroundPane(let paneId):
            store.mutationCoordinator.backgroundPane(paneId)

        case .reactivatePane(let paneId, let targetTabId, let targetPaneId, let direction):
            let layoutDirection = bridgeDirection(direction)
            let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after
            store.mutationCoordinator.reactivatePane(
                paneId,
                inTab: targetTabId,
                at: targetPaneId,
                direction: layoutDirection,
                position: position,
                sizingMode: .halveTarget
            )
            viewRegistry.ensureSlot(for: paneId)
            if viewRegistry.view(for: paneId) == nil, let pane = store.paneAtom.pane(paneId) {
                ensureTerminalPaneView(pane)
            }

        case .purgeOrphanedPane(let paneId):
            guard let pane = store.paneAtom.pane(paneId), pane.residency == .backgrounded else { break }
            teardownView(for: paneId)
            store.paneAtom.purgeOrphanedPane(paneId)
            viewRegistry.removeSlot(for: paneId)

        case .enterDrawer,
            .focusDrawerPaneUp,
            .focusDrawerPaneLeft,
            .focusDrawerPaneDown,
            .focusDrawerPaneRight:
            break

        case .detachDrawerPane(let parentPaneId, let drawerPaneId):
            guard let tabId = store.tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id else {
                Self.logger.warning("detachDrawerPane: parent pane \(parentPaneId) is not in a visible tab")
                break
            }

            guard store.paneAtom.detachDrawerPane(drawerPaneId, from: parentPaneId) != nil else {
                Self.logger.warning("detachDrawerPane: failed releasing drawer pane \(drawerPaneId)")
                break
            }

            store.tabLayoutAtom.insertPane(
                drawerPaneId,
                inTab: tabId,
                at: parentPaneId,
                direction: .horizontal,
                position: .after
            )
            store.tabLayoutAtom.setActivePane(drawerPaneId, inTab: tabId)
            restoreViewsForActiveTabIfNeeded()
            reattachForViewSwitch(paneId: drawerPaneId)
            focusVisiblePaneHost(drawerPaneId)

        case .addDrawerPane(let parentPaneId):
            let fallbackCWD = store.paneAtom.pane(parentPaneId)?.worktreeId.flatMap(
                store.repositoryTopologyAtom.worktree)?
                .path
            if let drawerPane = store.paneAtom.addDrawerPane(to: parentPaneId, parentFallbackCWD: fallbackCWD) {
                viewRegistry.ensureSlot(for: drawerPane.id)
                ensureTerminalPaneView(drawerPane)
                focusVisiblePaneHost(drawerPane.id)
            }

        case .removeDrawerPane(let parentPaneId, let drawerPaneId):
            let drawerBeforeRemoval = store.paneAtom.pane(parentPaneId)?.drawer
            let willBecomeEmptyDrawer =
                drawerBeforeRemoval?.paneIds.contains { $0 != drawerPaneId } == false
            if let drawer = drawerBeforeRemoval,
                drawer.activePaneId == drawerPaneId
            {
                let preRemovalFallbackPaneId = drawer.paneIds.first { candidatePaneId in
                    candidatePaneId != drawerPaneId && !drawer.minimizedPaneIds.contains(candidatePaneId)
                }
                if let preRemovalFallbackPaneId {
                    focusVisiblePaneHost(preRemovalFallbackPaneId)
                } else if willBecomeEmptyDrawer {
                    _ = clearFirstResponderToWindowContent(for: parentPaneId)
                } else {
                    focusVisiblePaneHost(parentPaneId)
                }
            }
            teardownView(for: drawerPaneId)
            store.paneAtom.removeDrawerPane(drawerPaneId, from: parentPaneId)
            viewRegistry.removeSlot(for: drawerPaneId)
            if let activeDrawerPaneId = store.paneAtom.pane(parentPaneId)?.drawer?.activePaneId {
                focusVisiblePaneHost(activeDrawerPaneId)
            } else if willBecomeEmptyDrawer {
                _ = clearFirstResponderToWindowContent(for: parentPaneId)
            } else {
                focusVisiblePaneHost(parentPaneId)
            }

        case .toggleDrawer(let paneId):
            store.paneAtom.toggleDrawer(for: paneId)
            if let drawer = store.paneAtom.pane(paneId)?.drawer,
                drawer.isExpanded,
                let activeDrawerPaneId = drawer.activePaneId
            {
                restoreViewsForActiveTabIfNeeded()
                focusVisiblePaneHost(activeDrawerPaneId)
            } else {
                focusVisiblePaneHost(paneId)
            }

        case .setActiveDrawerPane(let parentPaneId, let drawerPaneId):
            store.paneAtom.setActiveDrawerPane(drawerPaneId, in: parentPaneId)
            restoreViewsForActiveTabIfNeeded()
            focusVisiblePaneHost(drawerPaneId)

        case .resizeDrawerPane(let parentPaneId, let splitId, let ratio):
            store.paneAtom.resizeDrawerPane(parentPaneId: parentPaneId, splitId: splitId, ratio: ratio)

        case .equalizeDrawerPanes(let parentPaneId):
            store.paneAtom.equalizeDrawerPanes(parentPaneId: parentPaneId)

        case .minimizeDrawerPane(let parentPaneId, let drawerPaneId):
            if store.paneAtom.minimizeDrawerPane(drawerPaneId, in: parentPaneId) {
                detachForViewSwitch(paneId: drawerPaneId)
            }

        case .expandDrawerPane(let parentPaneId, let drawerPaneId):
            store.paneAtom.expandDrawerPane(drawerPaneId, in: parentPaneId)
            restoreVisiblePaneIfNeeded(drawerPaneId, forceWhenBoundsExist: true)
            if viewRegistry.terminalView(for: drawerPaneId) != nil {
                reattachForViewSwitch(paneId: drawerPaneId)
            }

        case .insertDrawerPane(let parentPaneId, let targetDrawerPaneId, let direction, let sizingMode):
            executeInsertDrawerPane(
                parentPaneId: parentPaneId,
                targetDrawerPaneId: targetDrawerPaneId,
                direction: direction,
                sizingMode: sizingMode
            )

        case .moveDrawerPane(let parentPaneId, let drawerPaneId, let target, let sizingMode):
            store.paneAtom.moveDrawerPane(
                drawerPaneId,
                in: parentPaneId,
                target: target,
                sizingMode: sizingMode
            )
            focusVisiblePaneHost(drawerPaneId)

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
        let pane = store.paneAtom.createPane(
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

        let tab = Tab(
            paneId: pane.id,
            name: tabNameForPane(pane)
        )
        store.tabLayoutAtom.appendTab(tab)
        store.tabLayoutAtom.setActiveTab(tab.id)
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

        if let snapshot = store.mutationCoordinator.snapshotForClose(tabId: tabId) {
            appendUndoEntry(.tab(snapshot))
        } else {
            Self.logger.warning("closeTab: snapshot failed for tab \(tabId); undo will be unavailable")
        }

        if let tab = store.tabLayoutAtom.tab(tabId) {
            // Close-tab keeps pane models alive for undo snapshots, so teardown only
            // unregisters hosts. Slots are intentionally preserved until the panes
            // are permanently purged from the store.
            for paneId in tab.allPaneIds {
                teardownDrawerPanes(for: paneId)
                teardownView(for: paneId)
            }
        }

        store.tabLayoutAtom.removeTab(tabId)
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
                store.mutationCoordinator.removePane(pane.id)
                viewRegistry.removeSlot(for: pane.id)
                Self.logger.debug("GC'd orphaned pane \(pane.id) from expired undo entry")
            }
        }
    }

    private func currentOwnedPaneIds() -> Set<UUID> {
        Set(
            store.tabLayoutAtom.tabs.flatMap { tab in
                tab.allPaneIds.flatMap { paneId -> [UUID] in
                    var paneIds = [paneId]
                    if let drawer = store.paneAtom.pane(paneId)?.drawer {
                        paneIds.append(contentsOf: drawer.paneIds)
                    }
                    return paneIds
                }
            }
        )
    }

    private func executeBreakUpTab(_ tabId: UUID) {
        let newTabs = store.tabLayoutAtom.breakUpTab(tabId)
        for newTab in newTabs {
            guard let paneId = newTab.activePaneId else { continue }
            guard let pane = store.paneAtom.pane(paneId) else {
                Self.logger.warning("breakUpTab: pane \(paneId) missing while naming new tab \(newTab.id)")
                continue
            }
            store.tabLayoutAtom.renameTab(newTab.id, name: tabNameForPane(pane))
        }
    }

    private func executeClosePane(tabId: UUID, paneId: UUID) {
        guard let closingPane = store.paneAtom.pane(paneId) else {
            Self.logger.warning("closePane: pane \(paneId) not found")
            return
        }

        let shouldCreateUndoEntry: Bool
        if let tab = store.tabLayoutAtom.tab(tabId), tab.id == store.tabLayoutAtom.activeTabId {
            if closingPane.isDrawerChild {
                shouldCreateUndoEntry = closingPane.parentPaneId.map { tab.activePaneIds.contains($0) } ?? false
            } else {
                shouldCreateUndoEntry = tab.activePaneIds.contains(paneId)
            }
        } else {
            shouldCreateUndoEntry = false
        }

        if shouldCreateUndoEntry {
            if let snapshot = store.mutationCoordinator.snapshotForPaneClose(paneId: paneId, inTab: tabId) {
                appendUndoEntry(.pane(snapshot))
            } else {
                Self.logger.warning("closePane: snapshot failed for pane \(paneId) in tab \(tabId)")
            }
        } else {
            Self.logger.debug("closePane: skipping undo snapshot for non-visible pane \(paneId) in tab \(tabId)")
        }

        if closingPane.isDrawerChild {
            if let parentPaneId = closingPane.parentPaneId {
                execute(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
            } else {
                teardownView(for: paneId)
                store.mutationCoordinator.removePane(paneId)
                viewRegistry.removeSlot(for: paneId)
            }
            expireOldUndoEntries()
            return
        }

        let drawerChildIds = closingPane.drawer?.paneIds ?? []
        teardownDrawerPanes(for: paneId)
        teardownView(for: paneId)
        store.tabLayoutAtom.removePaneFromLayout(paneId, inTab: tabId)

        for drawerPaneId in drawerChildIds {
            store.paneAtom.removeDrawerPane(drawerPaneId, from: paneId)
            viewRegistry.removeSlot(for: drawerPaneId)
        }

        let allOwnedPaneIds = currentOwnedPaneIds()
        if !allOwnedPaneIds.contains(paneId) {
            store.mutationCoordinator.removePane(paneId)
            viewRegistry.removeSlot(for: paneId)
        }

        expireOldUndoEntries()
    }

    private func executeInsertPane(
        source: PaneSource,
        targetTabId: UUID,
        targetPaneId: UUID,
        direction: SplitNewDirection,
        sizingMode: DropSizingMode
    ) {
        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after

        switch source {
        case .existingPane(let paneId, let sourceTabId):
            guard store.paneAtom.pane(paneId) != nil else {
                Self.logger.warning("insertPane existingPane: pane \(paneId) not found")
                return
            }
            guard store.tabLayoutAtom.tab(sourceTabId) != nil else {
                Self.logger.warning("insertPane existingPane: source tab \(sourceTabId) not found")
                return
            }
            guard store.tabLayoutAtom.tab(targetTabId) != nil else {
                Self.logger.warning("insertPane existingPane: target tab \(targetTabId) not found")
                return
            }
            store.tabLayoutAtom.removePaneFromLayout(paneId, inTab: sourceTabId)
            store.tabLayoutAtom.insertPane(
                paneId, inTab: targetTabId, at: targetPaneId,
                direction: layoutDirection, position: position, sizingMode: sizingMode
            )

        case .newTerminal:
            let targetPane = store.paneAtom.pane(targetPaneId)
            if let resolved = resolvedWorktreeContext(for: targetPane) {
                let pane = store.paneAtom.createPane(
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

                store.tabLayoutAtom.insertPane(
                    pane.id, inTab: targetTabId, at: targetPaneId,
                    direction: layoutDirection, position: position, sizingMode: sizingMode
                )
                ensureTerminalPaneView(pane)
                return
            }

            let pane = store.paneAtom.createPane(
                source: .floating(
                    launchDirectory: targetPane?.metadata.cwd ?? targetPane?.metadata.launchDirectory,
                    title: nil
                ),
                provider: .zmx,
                facets: targetPane?.metadata.facets ?? .empty
            )
            viewRegistry.ensureSlot(for: pane.id)

            store.tabLayoutAtom.insertPane(
                pane.id, inTab: targetTabId, at: targetPaneId,
                direction: layoutDirection, position: position, sizingMode: sizingMode
            )
            ensureTerminalPaneView(pane)
        }
    }

}
