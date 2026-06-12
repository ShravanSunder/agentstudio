import AppKit
import Foundation

@MainActor
extension PaneCoordinator {
    struct RestoreAllViewsProgress {
        var restored = 0
        var drawerRestored = 0
        var failedPaneIds: [UUID] = []
        var failedDrawerPaneIds: [UUID] = []
        var restoredPaneIds: Set<UUID> = []
    }

    /// Recreate views for all restored panes in all tabs, including drawer panes.
    /// Called once at launch after store.restore() populates persisted state.
    ///
    /// Startup is staged so the active tab is restored first, then background tabs
    /// are hydrated cooperatively with yields to keep first-interaction latency low.
    func restoreAllViews(in terminalContainerBounds: CGRect? = nil) async {
        defer {
            viewRegistry.completeInitialRestore()
        }
        if let terminalContainerBounds {
            RestoreTrace.log(
                "restoreAllViews inputBounds=\(NSStringFromRect(terminalContainerBounds))"
            )
        } else {
            RestoreTrace.log("restoreAllViews inputBounds=nil")
        }
        let orderedPaneIds = TerminalRestoreScheduler.order(
            Self.orderedUniquePaneIds(store.tabLayoutAtom.tabs.flatMap(\.allPaneIds)).map(PaneId.init(uuid:)),
            resolver: visibilityTierResolver
        ).map(\.uuid)
        RestoreTrace.log(
            "restoreAllViews begin tabs=\(store.tabLayoutAtom.tabs.count) paneIds=\(orderedPaneIds.count) activeTab=\(store.tabLayoutAtom.activeTabId?.uuidString ?? "nil")"
        )
        guard !orderedPaneIds.isEmpty else {
            Self.logger.info("No panes to restore views for")
            RestoreTrace.log("restoreAllViews no panes")
            return
        }

        // Seed slots for all panes before creating any views.
        // Panes already exist in the store from store.restore().
        // SwiftUI body may run before restoreAllViews completes,
        // so slots must exist before the first createViewForContent call.
        let allPaneIds = store.tabLayoutAtom.tabs.flatMap(\.activePaneIds)
        for paneId in allPaneIds {
            viewRegistry.ensureSlot(for: paneId)
        }
        for pane in store.paneAtom.panes.values {
            if pane.drawer != nil, let drawerView = arrangementView.drawerView(forParent: pane.id) {
                for drawerPaneId in drawerView.layout.paneIds {
                    viewRegistry.ensureSlot(for: drawerPaneId)
                }
            }
        }

        let visiblePaneIds = orderedPaneIds.filter {
            visibilityTierResolver.tier(for: PaneId(uuid: $0)) == .p0Visible
        }
        let hiddenPaneIds = orderedPaneIds.filter {
            visibilityTierResolver.tier(for: PaneId(uuid: $0)) == .p1Hidden
        }
        let restoreStart = RestoreTrace.nowIfEnabled()
        var progress = RestoreAllViewsProgress()
        defer {
            logRestoreAllViewsDuration(
                start: restoreStart,
                paneCount: orderedPaneIds.count,
                visibleCount: visiblePaneIds.count,
                hiddenCount: hiddenPaneIds.count,
                progress: progress
            )
        }
        let liveHiddenSessionIds = await tracedHiddenLiveSessionIds(hiddenPaneCount: hiddenPaneIds.count)
        let resolvedPaneFramesByTabId = resolveInitialFramesByTabId(in: terminalContainerBounds)

        // Stage 1: restore currently visible panes first for fast first paint/interaction.
        for paneId in visiblePaneIds {
            restorePaneAndDrawers(
                paneId,
                resolvedPaneFramesByTabId: resolvedPaneFramesByTabId,
                liveHiddenSessionIds: liveHiddenSessionIds,
                progress: &progress
            )
        }

        if let activeTab = store.tabLayoutAtom.activeTab,
            let activePaneId = activeTab.activePaneId,
            let terminalView = viewRegistry.terminalView(for: activePaneId)
        {
            surfaceManager.syncFocus(activeSurfaceId: terminalView.surfaceId)
            RestoreTrace.log(
                "restoreAllViews syncFocus activeTab=\(activeTab.id) activePane=\(activePaneId) activeSurface=\(terminalView.surfaceId?.uuidString ?? "nil")"
            )
        }

        // Stage 2: restore eligible hidden panes cooperatively after visible work.
        for (index, paneId) in hiddenPaneIds.enumerated() {
            if Task.isCancelled { break }
            restorePaneAndDrawers(
                paneId,
                resolvedPaneFramesByTabId: resolvedPaneFramesByTabId,
                liveHiddenSessionIds: liveHiddenSessionIds,
                progress: &progress
            )
            if index.isMultiple(of: 2) {
                await Task.yield()
            }
        }

        Self.logger.info(
            "Restored \(progress.restored)/\(orderedPaneIds.count) pane views, \(progress.drawerRestored) drawer pane views"
        )
        if !progress.failedPaneIds.isEmpty || !progress.failedDrawerPaneIds.isEmpty {
            let failedPrimary = progress.failedPaneIds.map(\.uuidString).joined(separator: ", ")
            let failedDrawer = progress.failedDrawerPaneIds.map(\.uuidString).joined(separator: ", ")
            Self.logger.error(
                """
                restoreAllViews: failed view creation primary=[\(failedPrimary)] drawer=[\(failedDrawer)] \
                (panes remain in store/layout and may appear as placeholders)
                """
            )
        }

        RestoreTrace.log("restoreAllViews end restored=\(progress.restored) drawerRestored=\(progress.drawerRestored)")
    }

    func initialFrame(
        for pane: Pane,
        resolvedPaneFramesByTabId: [UUID: [UUID: CGRect]]
    ) -> NSRect? {
        let owningPaneId = pane.parentPaneId ?? pane.id
        guard let tab = store.tabLayoutAtom.tabContaining(paneId: owningPaneId) else {
            return nil
        }
        guard let frame = resolvedPaneFramesByTabId[tab.id]?[pane.id], !frame.isEmpty else {
            return nil
        }
        return NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }

    func resolveInitialFramesByTabId(in terminalContainerBounds: CGRect?) -> [UUID: [UUID: CGRect]] {
        guard let terminalContainerBounds else {
            Self.logger.warning("resolveInitialFramesByTabId: terminal container bounds unavailable")
            RestoreTrace.log("resolveInitialFramesByTabId unavailableBounds")
            return [:]
        }
        guard !terminalContainerBounds.isEmpty else {
            Self.logger.warning("resolveInitialFramesByTabId: terminal container bounds empty")
            RestoreTrace.log("resolveInitialFramesByTabId emptyBounds")
            return [:]
        }

        return store.tabLayoutAtom.tabs.reduce(into: [UUID: [UUID: CGRect]]()) { result, tab in
            var resolvedFrames = TerminalPaneGeometryResolver.resolveFrames(
                for: tab.layout,
                in: terminalContainerBounds,
                dividerThickness: AppStyles.General.Layout.paneGap,
                minimizedPaneIds: tab.activeMinimizedPaneIds,
                collapsedPaneWidth: AppStyles.Shell.PaneChrome.collapsedBarWidth
            )
            if resolvedFrames.isEmpty, !tab.layout.isEmpty {
                Self.logger.warning(
                    "resolveInitialFramesByTabId: no resolved frames for non-empty tab \(tab.id.uuidString, privacy: .public)"
                )
                RestoreTrace.log("resolveInitialFramesByTabId noFrames tab=\(tab.id)")
            }

            for paneId in tab.activePaneIds {
                guard
                    let parentFrame = resolvedFrames[paneId],
                    let drawer = store.paneAtom.pane(paneId)?.drawer,
                    drawer.isExpanded,
                    let drawerView = arrangementView.drawerView(forParent: paneId),
                    let drawerContentRect = resolvedDrawerContentRect(
                        parentPaneFrame: parentFrame,
                        tabSize: terminalContainerBounds.size
                    )
                else {
                    if store.paneAtom.pane(paneId)?.drawer?.isExpanded == true {
                        Self.logger.warning(
                            "resolveInitialFramesByTabId: missing expanded drawer geometry for parent pane \(paneId.uuidString, privacy: .public)"
                        )
                        RestoreTrace.log("resolveInitialFramesByTabId missingDrawerGeometry parent=\(paneId)")
                    }
                    continue
                }
                let drawerFrames = TerminalPaneGeometryResolver.resolveFrames(
                    for: drawerView.layout,
                    in: drawerContentRect,
                    dividerThickness: AppStyles.General.Layout.paneGap,
                    minimizedPaneIds: drawerView.minimizedPaneIds,
                    collapsedPaneWidth: AppStyles.Shell.PaneChrome.collapsedBarWidth
                )

                for (drawerPaneId, drawerPaneFrame) in drawerFrames {
                    resolvedFrames[drawerPaneId] = drawerPaneFrame
                }
            }

            result[tab.id] = resolvedFrames
        }
    }

    private static func orderedUniquePaneIds(_ paneIds: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return paneIds.filter { seen.insert($0).inserted }
    }

    private func tracedHiddenLiveSessionIds(hiddenPaneCount: Int) async -> Set<String> {
        let hiddenDiscoveryStart = RestoreTrace.nowIfEnabled()
        let liveHiddenSessionIds = await hiddenLiveSessionIds()
        RestoreTrace.logDuration(
            "zmx_hidden_discovery",
            start: hiddenDiscoveryStart,
            fields: [
                ("hidden", "\(hiddenPaneCount)"),
                ("liveSessions", "\(liveHiddenSessionIds.count)"),
            ]
        )
        return liveHiddenSessionIds
    }

    private func hiddenLiveSessionIds() async -> Set<String> {
        let hiddenZmxPaneIds = store.paneAtom.panes.values.compactMap { pane -> UUID? in
            guard pane.provider == .zmx else { return nil }
            let paneId = PaneId(uuid: pane.id)
            return visibilityTierResolver.tier(for: paneId) == .p1Hidden ? pane.id : nil
        }
        let needsHiddenSessionDiscovery = !hiddenZmxPaneIds.isEmpty
        if !needsHiddenSessionDiscovery {
            return []
        }
        return await terminalRestoreRuntime.discoverLiveSessionIds()
    }

    private func shouldRestoreHiddenPane(
        _ pane: Pane,
        liveHiddenSessionIds: Set<String>
    ) -> Bool {
        let paneId = PaneId(uuid: pane.id)
        guard visibilityTierResolver.tier(for: paneId) == .p1Hidden else {
            return true
        }
        return terminalRestoreRuntime.shouldRestoreHiddenPane(
            pane,
            store: store,
            liveSessionIds: liveHiddenSessionIds
        )
    }

    private func restorePaneAndDrawers(
        _ paneId: UUID,
        resolvedPaneFramesByTabId: [UUID: [UUID: CGRect]],
        liveHiddenSessionIds: Set<String>,
        progress: inout RestoreAllViewsProgress
    ) {
        guard progress.restoredPaneIds.insert(paneId).inserted else { return }
        let paneRestoreStart = RestoreTrace.nowIfEnabled()
        defer {
            RestoreTrace.logDuration(
                "pane_restore",
                start: paneRestoreStart,
                fields: restoreTraceFields(forPaneId: paneId)
            )
        }
        guard let pane = store.paneAtom.pane(paneId) else {
            Self.logger.warning("Skipping view restore for pane \(paneId) — not in store")
            RestoreTrace.log("restoreAllViews skip missing pane=\(paneId)")
            return
        }
        guard shouldRestoreHiddenPane(pane, liveHiddenSessionIds: liveHiddenSessionIds) else {
            RestoreTrace.log("restoreAllViews skip hidden pane=\(paneId) reason=policy")
            restoreDrawerPanes(
                for: pane,
                resolvedPaneFramesByTabId: resolvedPaneFramesByTabId,
                liveHiddenSessionIds: liveHiddenSessionIds,
                progress: &progress
            )
            return
        }

        RestoreTrace.log("restoreAllViews restoring pane=\(paneId) content=\(String(describing: pane.content))")
        if viewRegistry.view(for: paneId) != nil {
            progress.restored += 1
        } else {
            let restoredView = createViewForContent(
                pane: pane,
                initialFrame: initialFrame(for: pane, resolvedPaneFramesByTabId: resolvedPaneFramesByTabId),
                treatAsRestoredSessionStart: true
            )
            if restoredView != nil {
                progress.restored += 1
            } else {
                progress.failedPaneIds.append(paneId)
            }
        }

        restoreDrawerPanes(
            for: pane,
            resolvedPaneFramesByTabId: resolvedPaneFramesByTabId,
            liveHiddenSessionIds: liveHiddenSessionIds,
            progress: &progress
        )
    }

    private func restoreDrawerPanes(
        for parentPane: Pane,
        resolvedPaneFramesByTabId: [UUID: [UUID: CGRect]],
        liveHiddenSessionIds: Set<String>,
        progress: inout RestoreAllViewsProgress
    ) {
        guard let drawer = parentPane.drawer else { return }
        for drawerPaneId in drawer.paneIds {
            guard progress.restoredPaneIds.insert(drawerPaneId).inserted else { continue }
            guard let drawerPane = store.paneAtom.pane(drawerPaneId) else {
                Self.logger.warning(
                    "restoreAllViews: drawer pane \(drawerPaneId) referenced by parent \(parentPane.id) is missing from store"
                )
                continue
            }
            guard shouldRestoreHiddenPane(drawerPane, liveHiddenSessionIds: liveHiddenSessionIds) else {
                RestoreTrace.log(
                    "restoreAllViews skip hidden drawer pane=\(drawerPaneId) parent=\(parentPane.id) reason=policy"
                )
                continue
            }
            RestoreTrace.log("restoreAllViews restoring drawer pane=\(drawerPaneId) parent=\(parentPane.id)")
            if viewRegistry.view(for: drawerPaneId) != nil {
                progress.drawerRestored += 1
            } else {
                let restoredView = createViewForContent(
                    pane: drawerPane,
                    initialFrame: initialFrame(
                        for: drawerPane,
                        resolvedPaneFramesByTabId: resolvedPaneFramesByTabId
                    ),
                    treatAsRestoredSessionStart: true
                )
                if restoredView != nil {
                    progress.drawerRestored += 1
                } else {
                    progress.failedDrawerPaneIds.append(drawerPaneId)
                }
            }
        }
    }

    private func resolvedDrawerContentRect(
        parentPaneFrame: CGRect,
        tabSize: CGSize
    ) -> CGRect? {
        guard tabSize.width > 0, tabSize.height > 0 else { return nil }

        let heightRatio = drawerHeightRatio()
        let panelWidth = tabSize.width * DrawerLayout.panelWidthRatio
        let panelHeight = max(
            DrawerLayout.panelMinHeight,
            min(tabSize.height * CGFloat(heightRatio), tabSize.height - DrawerLayout.panelBottomMargin)
        )
        let totalHeight = panelHeight + DrawerLayout.overlayConnectorHeight
        let overlayBottomY = parentPaneFrame.maxY - DrawerLayout.iconBarFrameHeight
        let centerY = overlayBottomY - totalHeight / 2
        let halfPanel = panelWidth / 2
        let edgeMargin = DrawerLayout.tabEdgeMargin
        let centerX = max(
            halfPanel + edgeMargin,
            min(tabSize.width - halfPanel - edgeMargin, parentPaneFrame.midX)
        )
        let panelLeft = centerX - halfPanel
        let panelTop = centerY - totalHeight / 2

        let contentRect = CGRect(
            x: panelLeft + DrawerLayout.panelContentPadding,
            y: panelTop + DrawerLayout.resizeHandleHeight,
            width: max(panelWidth - (DrawerLayout.panelContentPadding * 2), 1),
            height: max(
                panelHeight - DrawerLayout.resizeHandleHeight - DrawerLayout.panelContentPadding,
                1
            )
        )
        return contentRect.isEmpty ? nil : contentRect
    }

    private func drawerHeightRatio() -> Double {
        let storedValue = UserDefaults.standard.object(forKey: "drawerHeightRatio") as? Double
        return storedValue ?? DrawerLayout.heightRatioMax
    }
}
