import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTerminal
import AppKit

@MainActor
extension WorkspaceSurfaceCoordinator {
    func restoreViewsForActiveTabIfNeeded(forceWhenBoundsExist: Bool = false) {
        let clock = ContinuousClock()
        let restoreStart = clock.now
        guard let activeTab = store.tabLayoutAtom.activeTab else { return }
        let visiblePaneIDs = foregroundVisiblePaneIDs(in: activeTab)
        if !windowLifecycleStore.isLaunchLayoutSettled {
            let hasPreparingPlaceholder = visiblePaneIDs.contains { paneId in
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
            _ = preparedContentVisibilitySignalHandler(
                visiblePaneIDs.map(PaneId.init(existingUUID:))
            )
            RestoreTrace.log(
                "restoreViewsForActiveTabIfNeeded signalledPreparedOwners activeTab=\(activeTab.id) visiblePaneCount=\(visiblePaneIDs.count)"
            )
            return
        }

        let resolvedPaneFramesByTabId = [
            activeTab.id: resolveInitialFrames(for: activeTab, in: terminalContainerBounds)
        ]
        restoreMissingVisibleViews(
            visiblePaneIDs,
            in: activeTab,
            resolvedPaneFramesByTabId: resolvedPaneFramesByTabId,
            forceFailedPlaceholderRetry: forceWhenBoundsExist
        )
        performanceTraceRecorder?.recordDuration(
            .paneViewRestore,
            duration: restoreStart.duration(to: clock.now),
            attributes: [
                "agentstudio.performance.pane_view_restore.force_when_bounds_exist": .bool(forceWhenBoundsExist),
                "agentstudio.performance.pane_view_restore.pane.count": .int(activeTab.allPaneIds.count),
                "agentstudio.performance.pane_view_restore.visible_pane.count": .int(visiblePaneIDs.count),
                "agentstudio.performance.pane_view_restore.tab.count": .int(1),
            ]
        )
    }

    private func foregroundVisiblePaneIDs(in activeTab: Tab) -> [UUID] {
        TerminalRestoreScheduler.order(
            activeTab.allPaneIds.map { PaneId(existingUUID: $0) },
            resolver: visibilityTierResolver
        )
        .filter { visibilityTierResolver.tier(for: $0) == .p0Visible }
        .map(\.uuid)
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
