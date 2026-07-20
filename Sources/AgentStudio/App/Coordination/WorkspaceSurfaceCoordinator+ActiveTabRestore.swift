import AppKit

@MainActor
extension WorkspaceSurfaceCoordinator {
    func restoreViewsForActiveTabIfNeeded(forceWhenBoundsExist: Bool = false) {
        let clock = ContinuousClock()
        let restoreStart = clock.now
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
        guard forceWhenBoundsExist || activeTabHasMissingVisibleView(activeTab) else { return }
        RestoreTrace.log(
            "restoreViewsForActiveTabIfNeeded activeTab=\(activeTab.id) bounds=\(NSStringFromRect(terminalContainerBounds))"
        )
        if viewRegistry.isInitialRestorePending {
            let activePaneIDs = activeTab.activePaneIds.map(PaneId.init(existingUUID:))
            _ = preparedContentVisibilitySignalHandler(activePaneIDs)
            RestoreTrace.log(
                "restoreViewsForActiveTabIfNeeded signalledPreparedOwners activeTab=\(activeTab.id) visiblePaneCount=\(activeTab.activePaneIds.count)"
            )
            return
        }

        let visiblePaneIds = TerminalRestoreScheduler.order(
            store.paneAtom.panes.keys.map { PaneId(existingUUID: $0) },
            resolver: visibilityTierResolver
        )
        .filter { visibilityTierResolver.tier(for: $0) == .p0Visible }
        .map(\.uuid)
        let resolvedPaneFramesByTabId = resolveInitialFramesByTabId(in: terminalContainerBounds)
        restoreMissingVisibleViews(
            visiblePaneIds,
            in: activeTab,
            resolvedPaneFramesByTabId: resolvedPaneFramesByTabId,
            forceFailedPlaceholderRetry: forceWhenBoundsExist
        )
        performanceTraceRecorder?.recordDuration(
            .paneViewRestore,
            duration: restoreStart.duration(to: clock.now),
            attributes: [
                "agentstudio.performance.pane_view_restore.force_when_bounds_exist": .bool(forceWhenBoundsExist),
                "agentstudio.performance.pane_view_restore.pane.count": .int(store.paneAtom.panes.count),
                "agentstudio.performance.pane_view_restore.visible_pane.count": .int(visiblePaneIds.count),
                "agentstudio.performance.pane_view_restore.tab.count": .int(store.tabLayoutAtom.tabs.count),
            ]
        )
    }

    private func restoreMissingVisibleViews(
        _ visiblePaneIds: [UUID],
        in activeTab: Tab,
        resolvedPaneFramesByTabId: [UUID: [UUID: CGRect]],
        forceFailedPlaceholderRetry: Bool
    ) {
        for paneId in visiblePaneIds {
            guard let pane = store.paneAtom.pane(paneId) else { continue }
            guard paneBelongsToActiveTab(pane, activeTab: activeTab) else { continue }
            if let placeholder = viewRegistry.terminalStatusPlaceholderView(for: paneId) {
                guard forceFailedPlaceholderRetry || placeholder.shouldRetryCreationWhenBoundsChange else {
                    continue
                }
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
