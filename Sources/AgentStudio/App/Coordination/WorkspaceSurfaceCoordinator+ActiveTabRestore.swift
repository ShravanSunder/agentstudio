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
        // Always record the complete current visible queued set — this is
        // no longer gated on the retired launch-window presentation flag,
        // which stops being a creation selector after this cutover. A pane
        // can remain prepared-owned (pending or geometry-deferred) long after
        // launch settles, and this signal is also what feeds the scheduler's
        // promotion snapshot (SPEC R3). Nonterminal panes the prepared lane
        // still owns are excluded here; a terminal pane's actual creation
        // gate is its own per-pane `TerminalSurfaceCreationAuthority`,
        // resolved later inside `createViewForContent`.
        let visiblePaneIDList = visiblePaneIDs.map(PaneId.init(existingUUID:))
        let visibleQueuedSet = PreparedContentVisibleQueuedSet(
            visiblePaneIDs: visiblePaneIDList,
            activePaneIDs: Set(visiblePaneIDList.filter { visibilityTierResolver.isActive($0) })
        )
        let preparedHandledPaneIDs = preparedContentVisibilitySignalHandler(visibleQueuedSet)
        RestoreTrace.log(
            "restoreViewsForActiveTabIfNeeded signalledPreparedOwners activeTab=\(activeTab.id) visiblePaneCount=\(visiblePaneIDs.count) handledPaneCount=\(preparedHandledPaneIDs.count)"
        )
        let paneIDsToRestore = visiblePaneIDs.filter {
            !preparedHandledPaneIDs.contains(PaneId(existingUUID: $0))
        }
        guard !paneIDsToRestore.isEmpty else { return }

        let resolvedPaneFramesByTabId = [
            activeTab.id: resolveInitialFrames(for: activeTab, in: terminalContainerBounds)
        ]
        restoreMissingVisibleViews(
            paneIDsToRestore,
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

    /// The complete current visible-and-foreground pane set for `activeTab`,
    /// main panes before drawer panes. This ordering is a source-stability
    /// convenience only — it is not a contract for which pane is "active."
    /// `PreparedContentVisibleQueuedSet.activePaneIDs`, built separately from
    /// `visibilityTierResolver.isActive(_:)`, is the only signal callers may
    /// use for that. Shared with `+ViewHelpers.swift` and `+ViewLifecycle.swift`
    /// so every `preparedContentVisibilitySignalHandler` caller passes the
    /// complete current set rather than a single pane.
    func foregroundVisiblePaneIDs(in activeTab: Tab) -> [UUID] {
        let orderedVisiblePaneIDs = TerminalRestoreScheduler.order(
            activeTab.allPaneIds.map { PaneId(existingUUID: $0) },
            resolver: visibilityTierResolver
        )
        .filter { visibilityTierResolver.tier(for: $0) == .p0Visible }
        .map(\.uuid)
        let mainPaneIDs = orderedVisiblePaneIDs.filter {
            store.paneAtom.pane($0)?.parentPaneId == nil
        }
        let drawerPaneIDs = orderedVisiblePaneIDs.filter {
            store.paneAtom.pane($0)?.parentPaneId != nil
        }
        return mainPaneIDs + drawerPaneIDs
    }

    /// The complete current visible queued set for the active tab.
    /// `activePaneIDs` is computed directly from
    /// `visibilityTierResolver.isActive(_:)` — the same rule that decides the
    /// active main pane of the visible tab and, if a drawer is expanded, its
    /// active drawer pane — so this never duplicates that rule.
    func currentVisibleQueuedSet() -> PreparedContentVisibleQueuedSet {
        guard let activeTab = store.tabLayoutAtom.activeTab else {
            return PreparedContentVisibleQueuedSet(visiblePaneIDs: [], activePaneIDs: [])
        }
        let visiblePaneIDs = foregroundVisiblePaneIDs(in: activeTab).map(PaneId.init(existingUUID:))
        return PreparedContentVisibleQueuedSet(
            visiblePaneIDs: visiblePaneIDs,
            activePaneIDs: Set(visiblePaneIDs.filter { visibilityTierResolver.isActive($0) })
        )
    }

    /// Same as `currentVisibleQueuedSet()`, but guarantees `paneID` is present
    /// in `visiblePaneIDs` even when the active tab is unknown or the
    /// resolver's own tier check would otherwise exclude it — for example, a
    /// forced restore of a pane the resolver currently considers hidden.
    /// `paneID`'s own active membership is still decided by the resolver, not
    /// by this forced inclusion.
    func currentVisibleQueuedSet(includingAtLeast paneID: PaneId) -> PreparedContentVisibleQueuedSet {
        let base = currentVisibleQueuedSet()
        guard !base.visiblePaneIDs.contains(paneID) else { return base }
        var activePaneIDs = base.activePaneIDs
        if visibilityTierResolver.isActive(paneID) {
            activePaneIDs.insert(paneID)
        }
        return PreparedContentVisibleQueuedSet(
            visiblePaneIDs: base.visiblePaneIDs + [paneID],
            activePaneIDs: activePaneIDs
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
