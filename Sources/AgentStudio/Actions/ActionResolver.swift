import Foundation

/// Resolves user intents into fully-specified PaneActions.
/// Uses live state (including SplitTree navigation) to resolve
/// "active tab", "next pane", "neighbor in direction X" into concrete IDs.
///
/// Generic over `ResolvableTab` so resolution logic can be tested
/// with lightweight mocks (pure UUIDs, no NSViews).
///
/// Returns nil if the intent cannot be meaningfully resolved
/// (e.g., focusPaneLeft when there is no active tab).
enum ActionResolver {

    // MARK: - From AppCommand

    static func resolve<T: ResolvableTab>(
        command: AppCommand,
        tabs: [T],
        activeTabId: UUID?
    ) -> PaneAction? {
        switch command {
        // Tab lifecycle
        case .closeTab:
            guard let tabId = activeTabId else { return nil }
            return .closeTab(tabId: tabId)

        case .breakUpTab:
            guard let tabId = activeTabId else { return nil }
            return .breakUpTab(tabId: tabId)

        case .nextTab:
            guard let tabId = activeTabId,
                  let nextId = nextTabId(after: tabId, in: tabs) else { return nil }
            return .selectTab(tabId: nextId)

        case .prevTab:
            guard let tabId = activeTabId,
                  let prevId = previousTabId(before: tabId, in: tabs) else { return nil }
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
            return .closePane(tabId: tab.id, paneId: paneId)

        case .extractPaneToTab:
            guard let (tab, paneId) = activeTabAndPane(tabs: tabs, activeTabId: activeTabId)
            else { return nil }
            return .extractPaneToTab(tabId: tab.id, paneId: paneId)

        case .equalizePanes:
            guard let tabId = activeTabId else { return nil }
            return .equalizePanes(tabId: tabId)

        // Pane focus (directional → resolved ID)
        case .focusPaneLeft:
            return resolveFocusDirection(.left, tabs: tabs, activeTabId: activeTabId)
        case .focusPaneRight:
            return resolveFocusDirection(.right, tabs: tabs, activeTabId: activeTabId)
        case .focusPaneUp:
            return resolveFocusDirection(.up, tabs: tabs, activeTabId: activeTabId)
        case .focusPaneDown:
            return resolveFocusDirection(.down, tabs: tabs, activeTabId: activeTabId)

        case .focusNextPane:
            guard let (tab, paneId) = activeTabAndPane(tabs: tabs, activeTabId: activeTabId),
                  let nextId = tab.nextPaneId(after: paneId) else { return nil }
            return .focusPane(tabId: tab.id, paneId: nextId)

        case .focusPrevPane:
            guard let (tab, paneId) = activeTabAndPane(tabs: tabs, activeTabId: activeTabId),
                  let prevId = tab.previousPaneId(before: paneId) else { return nil }
            return .focusPane(tabId: tab.id, paneId: prevId)

        // Split directions (create new terminal)
        case .splitRight:
            return resolveSplit(.right, tabs: tabs, activeTabId: activeTabId)
        case .splitBelow:
            return resolveSplit(.down, tabs: tabs, activeTabId: activeTabId)
        case .splitLeft:
            return resolveSplit(.left, tabs: tabs, activeTabId: activeTabId)
        case .splitAbove:
            return resolveSplit(.up, tabs: tabs, activeTabId: activeTabId)

        case .toggleSplitZoom:
            guard let (tab, paneId) = activeTabAndPane(tabs: tabs, activeTabId: activeTabId)
            else { return nil }
            return .toggleSplitZoom(tabId: tab.id, paneId: paneId)

        // Non-pane commands: not resolved to PaneAction
        case .addRepo, .removeRepo, .refreshWorktrees,
             .toggleSidebar, .newFloatingTerminal,
             .newTerminalInTab, .newTab, .undoCloseTab,
             .newWindow, .closeWindow,
             .quickFind, .commandBar,
             .filterSidebar, .openNewTerminalInTab,
             .switchArrangement, .saveArrangement,
             .deleteArrangement, .renameArrangement:
            return nil
        }
    }

    // MARK: - From Drop Event

    static func resolveDrop(
        payload: SplitDropPayload,
        destinationPaneId: UUID,
        destinationTabId: UUID,
        zone: DropZone,
        state: ActionStateSnapshot
    ) -> PaneAction? {
        let direction = splitNewDirection(for: zone)

        switch payload.kind {
        case .existingTab(let tabId, _, _, _):
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
                guard let firstPaneId = sourceTab.paneIds.first else { return nil }
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
        isManagementModeActive: Bool
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: tabs.map { tab in
                TabSnapshot(
                    id: tab.id,
                    paneIds: tab.allPaneIds,
                    activePaneId: tab.activePaneId
                )
            },
            activeTabId: activeTabId,
            isManagementModeActive: isManagementModeActive
        )
    }

    // MARK: - Private Helpers

    private static func activeTabAndPane<T: ResolvableTab>(
        tabs: [T], activeTabId: UUID?
    ) -> (T, UUID)? {
        guard let tabId = activeTabId,
              let tab = tabs.first(where: { $0.id == tabId }),
              let paneId = tab.activePaneId else { return nil }
        return (tab, paneId)
    }

    private static func selectTabByIndex<T: ResolvableTab>(
        _ index: Int, tabs: [T]
    ) -> PaneAction? {
        guard index >= 0, index < tabs.count else { return nil }
        return .selectTab(tabId: tabs[index].id)
    }

    private static func nextTabId<T: ResolvableTab>(
        after tabId: UUID, in tabs: [T]
    ) -> UUID? {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }),
              tabs.count > 1 else { return nil }
        return tabs[(idx + 1) % tabs.count].id
    }

    private static func previousTabId<T: ResolvableTab>(
        before tabId: UUID, in tabs: [T]
    ) -> UUID? {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }),
              tabs.count > 1 else { return nil }
        return tabs[(idx - 1 + tabs.count) % tabs.count].id
    }

    private static func resolveFocusDirection<T: ResolvableTab>(
        _ direction: SplitFocusDirection,
        tabs: [T], activeTabId: UUID?
    ) -> PaneAction? {
        guard let (tab, paneId) = activeTabAndPane(tabs: tabs, activeTabId: activeTabId),
              let neighborId = tab.neighborPaneId(of: paneId, direction: direction)
        else { return nil }
        return .focusPane(tabId: tab.id, paneId: neighborId)
    }

    private static func resolveSplit<T: ResolvableTab>(
        _ direction: SplitNewDirection,
        tabs: [T], activeTabId: UUID?
    ) -> PaneAction? {
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
        case .left:   return .left
        case .right:  return .right
        case .top:    return .up
        case .bottom: return .down
        }
    }
}
