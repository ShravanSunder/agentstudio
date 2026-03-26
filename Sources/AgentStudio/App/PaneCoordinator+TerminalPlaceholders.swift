import Foundation

@MainActor
extension PaneCoordinator {
    @discardableResult
    /// Create a pane view using the current trusted terminal container bounds.
    /// Returns nil when bounds are unavailable or when pane-specific frame resolution fails.
    func createViewForContentUsingCurrentGeometry(
        pane: Pane,
        treatAsRestoredSessionStart: Bool = false
    ) -> PaneView? {
        let terminalContainerBounds = windowLifecycleStore.terminalContainerBounds
        guard !terminalContainerBounds.isEmpty else {
            RestoreTrace.log(
                "createViewForContentUsingCurrentGeometry deferred pane=\(pane.id) reason=emptyBounds"
            )
            registerTerminalPlaceholderIfNeeded(for: pane, mode: .preparing)
            return nil
        }

        let resolvedPaneFramesByTabId = resolveInitialFramesByTabId(in: terminalContainerBounds)
        return createViewForContent(
            pane: pane,
            initialFrame: initialFrame(for: pane, resolvedPaneFramesByTabId: resolvedPaneFramesByTabId),
            treatAsRestoredSessionStart: treatAsRestoredSessionStart
        )
    }

    @discardableResult
    func registerTerminalPlaceholderIfNeeded(
        for pane: Pane,
        mode: TerminalStatusPlaceholderMode
    ) -> TerminalStatusPlaceholderView? {
        guard case .terminal = pane.content, pane.provider == .zmx else { return nil }

        if let existingPlaceholder = viewRegistry.terminalStatusPlaceholderView(for: pane.id) {
            let previousMode = existingPlaceholder.mode
            existingPlaceholder.configure(mode: mode)
            if previousMode != mode {
                store.bumpViewRevision()
            }
            return existingPlaceholder
        }

        let placeholder = TerminalStatusPlaceholderView(
            paneId: pane.id,
            title: pane.metadata.title,
            mode: mode,
            onRetryRequested: { [weak self] paneId in
                self?.execute(.repair(.createMissingView(paneId: paneId)))
            },
            onDismissRequested: { [weak self] paneId in
                self?.closePlaceholderPane(paneId)
            }
        )
        viewRegistry.register(placeholder, for: pane.id)
        store.bumpViewRevision()
        return placeholder
    }

    private func closePlaceholderPane(_ paneId: UUID) {
        guard let tab = store.tabs.first(where: { $0.paneIds.contains(paneId) }) else { return }
        if tab.isSplit {
            execute(.closePane(tabId: tab.id, paneId: paneId))
        } else {
            execute(.closeTab(tabId: tab.id))
        }
    }

    func activeTabHasMissingVisibleView(_ activeTab: Tab) -> Bool {
        let visiblePaneIds = TerminalRestoreScheduler.order(
            store.panes.keys.map(PaneId.init(uuid:)),
            resolver: visibilityTierResolver
        )
        .filter { visibilityTierResolver.tier(for: $0) == .p0Visible }
        .map(\.uuid)

        for paneId in visiblePaneIds {
            guard let pane = store.pane(paneId) else { continue }
            guard store.tabContaining(paneId: pane.parentPaneId ?? pane.id)?.id == activeTab.id else {
                continue
            }
            if let placeholder = viewRegistry.terminalStatusPlaceholderView(for: paneId) {
                if placeholder.shouldRetryCreationWhenBoundsChange {
                    return true
                }
                continue
            }
            if viewRegistry.view(for: paneId) == nil {
                return true
            }
        }
        return false
    }
}
