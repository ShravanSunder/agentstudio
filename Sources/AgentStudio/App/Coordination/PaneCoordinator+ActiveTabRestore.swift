import AppKit

@MainActor
extension PaneCoordinator {
    func restoreViewsForActiveTabIfNeeded(forceWhenBoundsExist: Bool = false) {
        guard let activeTab = store.tabLayoutAtom.activeTab else { return }
        if !windowLifecycleStore.isLaunchLayoutSettled {
            let hasPreparingPlaceholder = activeTab.activePaneIds.contains { paneId in
                viewRegistry.terminalStatusPlaceholderView(for: paneId)?.shouldRetryCreationWhenBoundsChange == true
            }
            guard forceWhenBoundsExist || hasPreparingPlaceholder || windowLifecycleStore.isReadyForLaunchRestore else {
                RestoreTrace.log(
                    "restoreViewsForActiveTabIfNeeded skipped launchLayoutUnsettled bounds=\(NSStringFromRect(windowLifecycleStore.terminalContainerBounds)) settled=\(windowLifecycleStore.isLaunchLayoutSettled)"
                )
                return
            }
        }
        let terminalContainerBounds = windowLifecycleStore.terminalContainerBounds
        guard !terminalContainerBounds.isEmpty else {
            RestoreTrace.log("restoreViewsForActiveTabIfNeeded skipped boundsUnavailable")
            return
        }
        guard activeTabHasMissingVisibleView(activeTab) else { return }
        RestoreTrace.log(
            "restoreViewsForActiveTabIfNeeded activeTab=\(activeTab.id) bounds=\(NSStringFromRect(terminalContainerBounds))"
        )
        let resolvedPaneFramesByTabId = resolveInitialFramesByTabId(in: terminalContainerBounds)
        let visiblePaneIds = TerminalRestoreScheduler.order(
            store.paneAtom.panes.keys.map(PaneId.init(uuid:)),
            resolver: visibilityTierResolver
        )
        .filter { visibilityTierResolver.tier(for: $0) == .p0Visible }
        .map(\.uuid)

        if viewRegistry.isInitialRestorePending {
            restoreInitialVisibleViews(
                visiblePaneIds,
                in: activeTab,
                resolvedPaneFramesByTabId: resolvedPaneFramesByTabId
            )
            RestoreTrace.log(
                "restoreViewsForActiveTabIfNeeded initialRestoreVisibleViews activeTab=\(activeTab.id) visiblePaneCount=\(visiblePaneIds.count)"
            )
            return
        }

        restoreMissingVisibleViews(
            visiblePaneIds,
            in: activeTab,
            resolvedPaneFramesByTabId: resolvedPaneFramesByTabId
        )
    }

    private func restoreInitialVisibleViews(
        _ visiblePaneIds: [UUID],
        in activeTab: Tab,
        resolvedPaneFramesByTabId: [UUID: [UUID: CGRect]]
    ) {
        for paneId in visiblePaneIds {
            guard let pane = store.paneAtom.pane(paneId) else { continue }
            guard paneBelongsToActiveTab(pane, activeTab: activeTab) else { continue }
            guard viewRegistry.view(for: paneId) == nil else { continue }
            _ = createViewForContent(
                pane: pane,
                initialFrame: initialFrame(for: pane, resolvedPaneFramesByTabId: resolvedPaneFramesByTabId),
                treatAsRestoredSessionStart: true
            )
        }
    }

    private func restoreMissingVisibleViews(
        _ visiblePaneIds: [UUID],
        in activeTab: Tab,
        resolvedPaneFramesByTabId: [UUID: [UUID: CGRect]]
    ) {
        for paneId in visiblePaneIds {
            guard let pane = store.paneAtom.pane(paneId) else { continue }
            guard paneBelongsToActiveTab(pane, activeTab: activeTab) else { continue }
            if let placeholder = viewRegistry.terminalStatusPlaceholderView(for: paneId) {
                guard placeholder.shouldRetryCreationWhenBoundsChange else { continue }
            } else if viewRegistry.view(for: paneId) != nil {
                continue
            }
            _ = createViewForContent(
                pane: pane,
                initialFrame: initialFrame(for: pane, resolvedPaneFramesByTabId: resolvedPaneFramesByTabId),
                treatAsRestoredSessionStart: true
            )
        }
    }

    private func paneBelongsToActiveTab(_ pane: Pane, activeTab: Tab) -> Bool {
        store.tabLayoutAtom.tabContaining(paneId: pane.parentPaneId ?? pane.id)?.id == activeTab.id
    }
}
