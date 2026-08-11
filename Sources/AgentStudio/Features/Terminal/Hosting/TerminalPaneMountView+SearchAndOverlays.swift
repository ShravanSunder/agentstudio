import AgentStudioInfrastructure
import AppKit
import Observation

@MainActor
extension TerminalPaneMountView {
    func applyRuntimeStateSnapshot(_ runtime: TerminalRuntime) {
        if let scrollbarState = runtime.scrollbarState {
            let isEffectivelyPinnedToBottom =
                surfaceScrollView?.isEffectivelyPinnedToBottom(for: scrollbarState)
                ?? scrollbarState.isPinnedToBottom
            scrollToBottomIndicatorView?.applyScrollbarState(
                scrollbarState,
                isEffectivelyPinnedToBottom: isEffectivelyPinnedToBottom
            )
        }
        reconcileSearchPresentation(with: runtime.searchLifecycleState)
        if searchPresentationState.presentsOverlay {
            let isCreatingSearchOverlay = searchOverlayView == nil
            ensureSearchOverlay()
            if isCreatingSearchOverlay,
                runtime.searchLifecycleState.isActive,
                runtime.searchLifecycleState.epoch == searchPresentationState.epoch,
                let searchState = runtime.searchState
            {
                searchOverlayView?.initializeQuery(searchState.query)
            }
            if runtime.searchLifecycleState.isActive,
                runtime.searchLifecycleState.epoch == searchPresentationState.epoch,
                let searchState = runtime.searchState
            {
                searchOverlayView?.updateResults(
                    totalMatches: searchState.totalMatches,
                    selectedMatchIndex: searchState.selectedMatchIndex
                )
            }
        } else {
            hideSearchOverlay()
        }
    }

    @objc package func startSearch(_ sender: Any?) {
        if let searchOverlayView {
            searchOverlayView.focusSearchField()
            return
        }

        searchPresentationState = .opening(expectedEpoch: searchPresentationState.epoch &+ 1)
        ensureSearchOverlay()
        searchOverlayView?.focusSearchField()
        _ = currentActionPerformer?.performBindingAction(.startSearch)
    }

    @objc package func findNext(_ sender: Any?) {
        _ = currentActionPerformer?.performBindingAction(.navigateSearch(.next))
    }

    @objc package func findPrevious(_ sender: Any?) {
        _ = currentActionPerformer?.performBindingAction(.navigateSearch(.previous))
    }

    func handleSearchCancelOperation(_ sender: Any?) -> Bool {
        guard
            let searchOverlayView,
            searchOverlayView.ownsFirstResponder(window?.firstResponder)
        else {
            return false
        }

        return focusOwningTerminal()
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
        overlay.onReturnFocusToTerminal = { [weak self] in
            _ = self?.focusOwningTerminal()
        }
        overlay.onClose = { [weak self] in
            self?.endSearchAndHideOverlay()
        }
        addSubview(overlay)
        let preferredWidthConstraint = overlay.widthAnchor.constraint(
            equalTo: widthAnchor,
            constant: -(AppStyles.WorkspaceFocus.Terminal.searchOverlayHorizontalInset * 2)
        )
        preferredWidthConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(
                equalTo: topAnchor,
                constant: AppStyles.WorkspaceFocus.Terminal.searchOverlayHorizontalInset
            ),
            overlay.centerXAnchor.constraint(equalTo: centerXAnchor),
            overlay.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: AppStyles.WorkspaceFocus.Terminal.searchOverlayHorizontalInset
            ),
            overlay.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -AppStyles.WorkspaceFocus.Terminal.searchOverlayHorizontalInset
            ),
            overlay.widthAnchor.constraint(
                lessThanOrEqualToConstant:
                    AppStyles.WorkspaceFocus.Terminal.searchOverlayMaximumWidth
            ),
            preferredWidthConstraint,
            overlay.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        searchOverlayView = overlay
        overlay.focusSearchField()
    }

    func hideSearchOverlay() {
        searchOverlayView?.removeFromSuperview()
        searchOverlayView = nil
    }

    private func endSearchAndHideOverlay() {
        searchPresentationState = .closing(expectedEpoch: searchPresentationState.epoch)
        _ = currentActionPerformer?.performBindingAction(.endSearch)
        hideSearchOverlay()
        _ = focusOwningTerminal()
    }

    private func reconcileSearchPresentation(
        with lifecycleState: TerminalSearchLifecycleState
    ) {
        let observedEpoch = lifecycleState.epoch

        switch searchPresentationState {
        case .opening(let expectedEpoch):
            guard observedEpoch >= expectedEpoch else {
                return
            }
        case .closing(let expectedEpoch):
            guard observedEpoch >= expectedEpoch else {
                return
            }
            if observedEpoch == expectedEpoch, lifecycleState.isActive {
                return
            }
        case .closed(let epoch), .open(let epoch):
            guard observedEpoch >= epoch else {
                return
            }
        }

        searchPresentationState =
            lifecycleState.isActive
            ? .open(epoch: observedEpoch)
            : .closed(epoch: observedEpoch)
    }

    private func focusOwningTerminal() -> Bool {
        guard let window else {
            return false
        }
        return window.makeFirstResponder(self)
    }

    func ensureScrollToBottomIndicator() {
        guard scrollToBottomIndicatorView == nil else { return }
        let indicator = ScrollToBottomIndicatorView()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.actionPerformer = currentActionPerformer
        addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            indicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        scrollToBottomIndicatorView = indicator
    }

    func observeRuntimeState(runtime: TerminalRuntime) {
        withObservationTracking {
            _ = runtime.scrollbarState
            _ = runtime.cellSize
            _ = runtime.searchState
            _ = runtime.searchLifecycleState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let currentRuntime = self.boundRuntime, currentRuntime === runtime else { return }
                self.applyRuntimeStateSnapshot(currentRuntime)
                self.observeRuntimeState(runtime: currentRuntime)
            }
        }
    }

    func resolvedHitTest(for point: NSPoint) -> NSView? {
        if let overlay = searchOverlayView {
            let overlayPoint = convert(point, to: overlay)
            if overlay.bounds.contains(overlayPoint) {
                return overlay.hitTest(point) ?? overlay
            }
        }

        if let indicator = scrollToBottomIndicatorView, !indicator.isHidden {
            let indicatorPoint = convert(point, to: indicator)
            if indicator.bounds.contains(indicatorPoint) {
                return indicator.hitTest(point) ?? indicator
            }
        }

        if let overlay = errorOverlay, !overlay.isHidden {
            let overlayPoint = convert(point, to: overlay)
            if overlay.bounds.contains(overlayPoint) {
                return overlay.hitTest(point)
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

        func simulateSurfaceCloseForTesting(processAlive: Bool) -> Task<Void, Never>? {
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
