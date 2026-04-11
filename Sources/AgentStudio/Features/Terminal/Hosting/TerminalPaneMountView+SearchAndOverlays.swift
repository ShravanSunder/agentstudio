import AppKit
import Observation

@MainActor
extension TerminalPaneMountView {
    @objc func startSearch(_ sender: Any?) {
        ensureSearchOverlay()
        _ = currentActionPerformer?.performBindingAction(.startSearch)
    }

    @objc func findNext(_ sender: Any?) {
        _ = currentActionPerformer?.performBindingAction(.navigateSearch(.next))
    }

    @objc func findPrevious(_ sender: Any?) {
        _ = currentActionPerformer?.performBindingAction(.navigateSearch(.previous))
    }

    func handleSearchCancelOperation(_ sender: Any?) -> Bool {
        guard searchOverlayView != nil else {
            return false
        }

        _ = currentActionPerformer?.performBindingAction(.endSearch)
        hideSearchOverlay()
        return true
    }

    func ensureSearchOverlay() {
        guard searchOverlayView == nil else { return }

        let overlay = TerminalSearchOverlayView()
        overlay.onQueryChanged = { [weak self] query in
            _ = self?.currentActionPerformer?.performBindingAction(.search(query))
        }
        overlay.onNavigate = { [weak self] direction in
            let actionDirection: TerminalSurfaceAction.SearchDirection =
                direction == .next ? .next : .previous
            _ = self?.currentActionPerformer?.performBindingAction(.navigateSearch(actionDirection))
        }
        overlay.onClose = { [weak self] in
            _ = self?.currentActionPerformer?.performBindingAction(.endSearch)
            self?.hideSearchOverlay()
        }
        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            overlay.centerXAnchor.constraint(equalTo: centerXAnchor),
            overlay.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            overlay.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        searchOverlayView = overlay
    }

    func hideSearchOverlay() {
        searchOverlayView?.removeFromSuperview()
        searchOverlayView = nil
    }

    func ensureScrollToBottomIndicator() {
        guard scrollToBottomIndicatorView == nil else { return }
        let indicator = ScrollToBottomIndicatorView()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.actionPerformer = currentActionPerformer
        addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            indicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
        scrollToBottomIndicatorView = indicator
    }

    func observeRuntimeState(runtime: TerminalRuntime) {
        withObservationTracking {
            _ = runtime.scrollbarState
            _ = runtime.cellSize
            _ = runtime.searchState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let currentRuntime = self.boundRuntime, currentRuntime === runtime else { return }
                if let scrollbarState = currentRuntime.scrollbarState {
                    self.surfaceScrollView?.applyScrollbarState(
                        scrollbarState,
                        cellHeight: currentRuntime.cellSize.height
                    )
                    self.scrollToBottomIndicatorView?.applyScrollbarState(scrollbarState)
                }
                if let searchState = currentRuntime.searchState {
                    self.ensureSearchOverlay()
                    self.searchOverlayView?.update(
                        query: searchState.query,
                        totalMatches: searchState.totalMatches,
                        selectedMatchIndex: searchState.selectedMatchIndex
                    )
                } else {
                    self.hideSearchOverlay()
                }
                self.observeRuntimeState(runtime: currentRuntime)
            }
        }
    }

    func resolvedHitTest(for point: NSPoint) -> NSView? {
        if let overlay = searchOverlayView {
            let overlayPoint = convert(point, to: overlay)
            if overlay.bounds.contains(overlayPoint) {
                return overlay.hitTest(overlayPoint) ?? overlay
            }
        }

        if let indicator = scrollToBottomIndicatorView, !indicator.isHidden {
            let indicatorPoint = convert(point, to: indicator)
            if indicator.bounds.contains(indicatorPoint) {
                return indicator.hitTest(indicatorPoint) ?? indicator
            }
        }

        if let overlay = errorOverlay, !overlay.isHidden {
            let overlayPoint = convert(point, to: overlay)
            if overlay.bounds.contains(overlayPoint) {
                return overlay.hitTest(overlayPoint)
            }
        }

        return nil
    }
}

#if DEBUG
    @MainActor
    extension TerminalPaneMountView {
        var placeholderViewForTesting: TerminalStatusPlaceholderView? { placeholderView }

        func beginRestorePresentationForTesting() {
            beginRestorePresentationIfNeeded()
        }

        func simulateSurfaceCloseForTesting(processAlive: Bool) {
            handleSurfaceClose(processAlive: processAlive)
        }

        func applyHealthUpdateForTesting(_ health: SurfaceHealth) {
            updateHealthUI(health)
        }

        var isShowingStartupOverlayForTesting: Bool {
            startupOverlay?.isHidden == false
        }

        var isProcessExitedOverlaySuppressedAfterTerminationForTesting: Bool {
            shouldSuppressProcessExitedOverlayAfterTermination
        }

        var hasObservedEffectiveTerminationDeliveryForTesting: Bool {
            hasObservedEffectiveTerminationDelivery
        }

        var isShowingErrorOverlayForTesting: Bool {
            errorOverlay?.isHidden == false
        }

        func ensureSearchOverlayForTesting() {
            ensureSearchOverlay()
            layoutSubtreeIfNeeded()
        }

        func ensureScrollToBottomIndicatorForTesting() {
            ensureScrollToBottomIndicator()
            layoutSubtreeIfNeeded()
        }

        var searchOverlayFrameForTesting: NSRect? {
            searchOverlayView?.frame
        }

        var searchOverlayInteractivePointForTesting: NSPoint? {
            guard let searchOverlayView else { return nil }
            let pointInOverlay = searchOverlayView.interactivePointForTesting
            return convert(pointInOverlay, from: searchOverlayView)
        }

        var scrollToBottomIndicatorFrameForTesting: NSRect? {
            scrollToBottomIndicatorView?.frame
        }
    }
#endif
