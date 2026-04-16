// swiftlint:disable cyclomatic_complexity
import Foundation

/// Resolves workspace commands into fully-specified pane actions.
/// Uses live state to resolve structural tab/pane mutations into concrete IDs.
/// Pane focus navigation commands no longer resolve here; they route through
/// the Pane Focus System in PaneTabViewController.
///
/// Generic over `ResolvableTab` so resolution logic can be tested
/// with lightweight mocks (pure UUIDs, no NSViews).
///
/// Returns nil if the intent cannot be meaningfully resolved.
enum WorkspaceCommandResolver {

    // MARK: - From AppCommand

    static func resolve<T: ResolvableTab>(
        command: AppCommand,
        tabs: [T],
        activeTabId: UUID?
    ) -> PaneActionCommand? {
        if isNonPaneCommand(command) {
            return nil
        }

        switch command {
        // Tab lifecycle
        case .selectTab:
            return nil
        case .closeTab:
            guard let tabId = activeTabId else { return nil }
            return .closeTab(tabId: tabId)

        case .renameTab:
            return nil

        case .breakUpTab:
            guard let tabId = activeTabId else { return nil }
            return .breakUpTab(tabId: tabId)

        case .nextTab:
            guard let tabId = activeTabId,
                let nextId = nextTabId(after: tabId, in: tabs)
            else { return nil }
            return .selectTab(tabId: nextId)

        case .prevTab:
            guard let tabId = activeTabId,
                let prevId = previousTabId(before: tabId, in: tabs)
            else { return nil }
            return .selectTab(tabId: prevId)

        case .selectTab1: return selectTabByIndex(0, tabs: tabs)
        case .selectTab2: return selectTabByIndex(1, tabs: tabs)
        case .selectTab3: return selectTabByIndex(2, tabs: tabs)
        case .selectTab4: return selectTabByIndex(3, tabs: tabs)
        case .selectTab5: return selectTabByIndex(4, tabs: tabs)
        case .selectTab6: return selectTabByIndex(5, tabs: tabs)
        case .selectTab7: return selectTabByIndex(6, tabs: tabs)
        case .selectTab8: return selectTabByIndex(7, tabs: tabs)
        case .selectTab9: return selectTabByIndex(8, tabs: tabs)

        // Pane lifecycle
        case .closePane:
            guard let (tab, paneId) = activeTabAndPane(tabs: tabs, activeTabId: activeTabId)
            else { return nil }
            if tab.visiblePaneIds.count <= 1 {
                return .closeTab(tabId: tab.id)
            }
            return .closePane(tabId: tab.id, paneId: paneId)

        case .focusPane:
            return nil
        case .extractPaneToTab:
            guard let (tab, paneId) = activeTabAndPane(tabs: tabs, activeTabId: activeTabId)
            else { return nil }
            return .extractPaneToTab(tabId: tab.id, paneId: paneId)

        case .movePaneToTab:
            return nil

        case .equalizePanes:
            guard let tabId = activeTabId else { return nil }
            return .equalizePanes(tabId: tabId)

        // Pane focus now routes through PaneFocusTrigger / PaneFocusDecision in PaneTabViewController.
        case .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane:
            return nil

        // Split directions (horizontal only — vertical splits disabled for drawers)
        case .splitRight:
            return resolveSplit(.right, tabs: tabs, activeTabId: activeTabId)
        case .splitLeft:
            return resolveSplit(.left, tabs: tabs, activeTabId: activeTabId)

        case .toggleSplitZoom:
            guard let (tab, paneId) = activeTabAndPane(tabs: tabs, activeTabId: activeTabId)
            else { return nil }
            return .toggleSplitZoom(tabId: tab.id, paneId: paneId)

        case .minimizePane:
            guard let (tab, paneId) = activeTabAndPane(tabs: tabs, activeTabId: activeTabId)
            else { return nil }
            return .minimizePane(tabId: tab.id, paneId: paneId)

        case .expandPane:
            guard let (tab, paneId) = activeTabAndPane(tabs: tabs, activeTabId: activeTabId)
            else { return nil }
            return .expandPane(tabId: tab.id, paneId: paneId)

        default:
            return nil
        }
    }

    private static func isNonPaneCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .addRepo, .addFolder, .removeRepo,
            .toggleSidebar, .newFloatingTerminal,
            .newTerminalInTab, .newTab, .undoCloseTab, .renameTab,
            .newWindow, .closeWindow,
            .showCommandBarEverything, .showCommandBarCommands,
            .showCommandBarPanes, .showCommandBarRepos,
            .openWebview, .signInGitHub, .signInGoogle,
            .filterSidebar, .openNewTerminalInTab, .openWorktree, .openWorktreeInPane,
            .switchArrangement, .saveArrangement,
            .deleteArrangement, .renameArrangement,
            .addDrawerPane, .toggleDrawer,
            .navigateDrawerPane, .closeDrawerPane,
            .toggleManagementLayer,
            .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit:
            return true
        default:
            return false
        }
    }

    // MARK: - From Drop Event

    static func resolveDrop(
        payload: SplitDropPayload,
        destinationPaneId: UUID,
        destinationTabId: UUID,
        zone: DropZone,
        state: ActionStateSnapshot
    ) -> PaneActionCommand? {
        let direction = splitNewDirection(for: zone)

        switch payload.kind {
        case .existingTab(let tabId):
            // Look up source tab by ID
            guard let sourceTab = state.tab(tabId) else { return nil }

            if sourceTab.isSplit {
                // Multi-pane tab: merge entire tab into target
                return .mergeTab(
                    sourceTabId: tabId,
                    targetTabId: destinationTabId,
                    targetPaneId: destinationPaneId,
                    direction: direction
                )
            } else {
                // Single pane: move individual pane
                guard let firstPaneId = sourceTab.visiblePaneIds.first else { return nil }
                return .insertPane(
                    source: .existingPane(paneId: firstPaneId, sourceTabId: tabId),
                    targetTabId: destinationTabId,
                    targetPaneId: destinationPaneId,
                    direction: direction
                )
            }

        case .existingPane(let paneId, let sourceTabId):
            return .insertPane(
                source: .existingPane(paneId: paneId, sourceTabId: sourceTabId),
                targetTabId: destinationTabId,
                targetPaneId: destinationPaneId,
                direction: direction
            )

        case .newTerminal:
            return .insertPane(
                source: .newTerminal,
                targetTabId: destinationTabId,
                targetPaneId: destinationPaneId,
                direction: direction
            )
        }
    }

    // MARK: - Snapshot Factory

    /// Build a validation snapshot from live tab state.
    static func snapshot<T: ResolvableTab>(
        from tabs: [T],
        activeTabId: UUID?,
        isManagementLayerActive: Bool,
        knownRepoIds: Set<UUID> = [],
        knownWorktreeIds: Set<UUID> = [],
        drawerParentByPaneId: [UUID: UUID] = [:]
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: tabs.map { tab in
                TabSnapshot(
                    id: tab.id,
                    visiblePaneIds: tab.visiblePaneIds,
                    ownedPaneIds: tab.ownedPaneIds,
                    activePaneId: tab.activePaneId
                )
            },
            activeTabId: activeTabId,
            isManagementLayerActive: isManagementLayerActive,
            knownRepoIds: knownRepoIds,
            knownWorktreeIds: knownWorktreeIds,
            drawerParentByPaneId: drawerParentByPaneId
        )
    }

    // MARK: - Private Helpers

    private static func activeTabAndPane<T: ResolvableTab>(
        tabs: [T], activeTabId: UUID?
    ) -> (T, UUID)? {
        guard let tabId = activeTabId,
            let tab = tabs.first(where: { $0.id == tabId }),
            let paneId = tab.activePaneId
        else { return nil }
        return (tab, paneId)
    }

    private static func selectTabByIndex<T: ResolvableTab>(
        _ index: Int, tabs: [T]
    ) -> PaneActionCommand? {
        guard index >= 0, index < tabs.count else { return nil }
        return .selectTab(tabId: tabs[index].id)
    }

    private static func nextTabId<T: ResolvableTab>(
        after tabId: UUID, in tabs: [T]
    ) -> UUID? {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }),
            tabs.count > 1
        else { return nil }
        return tabs[(idx + 1) % tabs.count].id
    }

    private static func previousTabId<T: ResolvableTab>(
        before tabId: UUID, in tabs: [T]
    ) -> UUID? {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }),
            tabs.count > 1
        else { return nil }
        return tabs[(idx - 1 + tabs.count) % tabs.count].id
    }

    private static func resolveSplit<T: ResolvableTab>(
        _ direction: SplitNewDirection,
        tabs: [T], activeTabId: UUID?
    ) -> PaneActionCommand? {
        guard let (tab, paneId) = activeTabAndPane(tabs: tabs, activeTabId: activeTabId)
        else { return nil }
        return .insertPane(
            source: .newTerminal,
            targetTabId: tab.id,
            targetPaneId: paneId,
            direction: direction
        )
    }

    private static func splitNewDirection(for zone: DropZone) -> SplitNewDirection {
        switch zone {
        case .left: return .left
        case .right: return .right
        }
    }
}
