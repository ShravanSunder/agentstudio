import Foundation

/// Wrapper that proves an action has passed validation.
/// Only ActionValidator can create instances (fileprivate init).
struct ValidatedAction: Equatable {
    let action: PaneAction

    fileprivate init(_ action: PaneAction) {
        self.action = action
    }
}

/// Validation errors for rejected actions.
enum ActionValidationError: Error, Equatable {
    case tabNotFound(tabId: UUID)
    case paneNotFound(paneId: UUID, tabId: UUID)
    case tabNotSplit(tabId: UUID)
    case singlePaneTab(tabId: UUID)
    case selfPaneInsertion(paneId: UUID)
    case selfTabMerge(sourceTabId: UUID)
    case sourcePaneNotFound(paneId: UUID, sourceTabId: UUID)
    case invalidRatio(ratio: Double)
    case paneAlreadyInLayout(paneId: UUID)
}

/// Pure-function validation engine.
/// Takes a resolved action and a state snapshot, returns validated or error.
/// No side effects, no UI dependencies, no NSViews.
enum ActionValidator {

    static func validate(
        _ action: PaneAction,
        state: ActionStateSnapshot
    ) -> Result<ValidatedAction, ActionValidationError> {
        switch action {
        case .selectTab(let tabId):
            guard state.tab(tabId) != nil else {
                return .failure(.tabNotFound(tabId: tabId))
            }
            return .success(ValidatedAction(action))

        case .closeTab(let tabId):
            guard state.tab(tabId) != nil else {
                return .failure(.tabNotFound(tabId: tabId))
            }
            return .success(ValidatedAction(action))

        case .breakUpTab(let tabId):
            guard let tab = state.tab(tabId) else {
                return .failure(.tabNotFound(tabId: tabId))
            }
            guard tab.isSplit else {
                return .failure(.tabNotSplit(tabId: tabId))
            }
            return .success(ValidatedAction(action))

        case .closePane(let tabId, let paneId):
            guard let tab = state.tab(tabId) else {
                return .failure(.tabNotFound(tabId: tabId))
            }
            guard tab.paneIds.contains(paneId) else {
                return .failure(.paneNotFound(paneId: paneId, tabId: tabId))
            }
            // Single-pane close is allowed — executor escalates to closeTab with undo.
            return .success(ValidatedAction(action))

        case .extractPaneToTab(let tabId, let paneId):
            guard let tab = state.tab(tabId) else {
                return .failure(.tabNotFound(tabId: tabId))
            }
            guard tab.paneIds.contains(paneId) else {
                return .failure(.paneNotFound(paneId: paneId, tabId: tabId))
            }
            guard tab.paneCount > 1 else {
                return .failure(.singlePaneTab(tabId: tabId))
            }
            return .success(ValidatedAction(action))

        case .focusPane(let tabId, let paneId):
            guard let tab = state.tab(tabId) else {
                return .failure(.tabNotFound(tabId: tabId))
            }
            guard tab.paneIds.contains(paneId) else {
                return .failure(.paneNotFound(paneId: paneId, tabId: tabId))
            }
            return .success(ValidatedAction(action))

        case .insertPane(let source, let targetTabId, let targetPaneId, _):
            guard state.tab(targetTabId) != nil else {
                return .failure(.tabNotFound(tabId: targetTabId))
            }
            guard state.tabContainsPane(targetTabId, paneId: targetPaneId) else {
                return .failure(.paneNotFound(paneId: targetPaneId, tabId: targetTabId))
            }
            if case .existingPane(let sourcePaneId, let sourceTabId) = source {
                guard state.tabContainsPane(sourceTabId, paneId: sourcePaneId) else {
                    return .failure(.sourcePaneNotFound(
                        paneId: sourcePaneId, sourceTabId: sourceTabId))
                }
                // Self-insertion check: can't drop a pane onto itself
                guard sourcePaneId != targetPaneId else {
                    return .failure(.selfPaneInsertion(paneId: sourcePaneId))
                }
            }
            return .success(ValidatedAction(action))

        case .resizePane(let tabId, _, let ratio):
            guard let tab = state.tab(tabId) else {
                return .failure(.tabNotFound(tabId: tabId))
            }
            guard tab.isSplit else {
                return .failure(.tabNotSplit(tabId: tabId))
            }
            guard ratio >= 0.1 && ratio <= 0.9 else {
                return .failure(.invalidRatio(ratio: ratio))
            }
            return .success(ValidatedAction(action))

        case .equalizePanes(let tabId):
            guard let tab = state.tab(tabId) else {
                return .failure(.tabNotFound(tabId: tabId))
            }
            guard tab.isSplit else {
                return .failure(.tabNotSplit(tabId: tabId))
            }
            return .success(ValidatedAction(action))

        case .mergeTab(let sourceTabId, let targetTabId, let targetPaneId, _):
            guard state.tab(sourceTabId) != nil else {
                return .failure(.tabNotFound(tabId: sourceTabId))
            }
            guard state.tab(targetTabId) != nil else {
                return .failure(.tabNotFound(tabId: targetTabId))
            }
            guard state.tabContainsPane(targetTabId, paneId: targetPaneId) else {
                return .failure(.paneNotFound(paneId: targetPaneId, tabId: targetTabId))
            }
            guard sourceTabId != targetTabId else {
                return .failure(.selfTabMerge(sourceTabId: sourceTabId))
            }
            return .success(ValidatedAction(action))

        case .toggleSplitZoom(let tabId, let paneId),
             .resizePaneByDelta(let tabId, let paneId, _, _),
             .minimizePane(let tabId, let paneId),
             .expandPane(let tabId, let paneId):
            if let error = validateTabContainsPane(tabId: tabId, paneId: paneId, state: state) {
                return .failure(error)
            }
            return .success(ValidatedAction(action))

        case .moveTab(let tabId, _):
            guard state.tab(tabId) != nil else {
                return .failure(.tabNotFound(tabId: tabId))
            }
            return .success(ValidatedAction(action))

        // Arrangement actions — validate tab exists
        case .createArrangement(let tabId, _, _),
             .removeArrangement(let tabId, _),
             .switchArrangement(let tabId, _),
             .renameArrangement(let tabId, _, _):
            guard state.tab(tabId) != nil else {
                return .failure(.tabNotFound(tabId: tabId))
            }
            return .success(ValidatedAction(action))

        // Orphaned pane pool — store-level
        case .backgroundPane, .purgeOrphanedPane:
            return .success(ValidatedAction(action))

        case .reactivatePane(_, let targetTabId, let targetPaneId, _):
            guard state.tab(targetTabId) != nil else {
                return .failure(.tabNotFound(tabId: targetTabId))
            }
            guard state.tabContainsPane(targetTabId, paneId: targetPaneId) else {
                return .failure(.paneNotFound(paneId: targetPaneId, tabId: targetTabId))
            }
            return .success(ValidatedAction(action))

        // Drawer actions — validate parent pane is in an active tab layout.
        // Store-level guards provide additional safety for panes in non-active arrangements.
        case .addDrawerPane(let parentPaneId, _, _):
            guard state.tabContaining(paneId: parentPaneId) != nil else {
                return .failure(.paneNotFound(paneId: parentPaneId, tabId: state.activeTabId ?? UUID()))
            }
            return .success(ValidatedAction(action))
        case .removeDrawerPane(let parentPaneId, _),
             .setActiveDrawerPane(let parentPaneId, _),
             .resizeDrawerPane(let parentPaneId, _, _),
             .equalizeDrawerPanes(let parentPaneId),
             .minimizeDrawerPane(let parentPaneId, _),
             .expandDrawerPane(let parentPaneId, _):
            guard state.tabContaining(paneId: parentPaneId) != nil else {
                return .failure(.paneNotFound(paneId: parentPaneId, tabId: state.activeTabId ?? UUID()))
            }
            return .success(ValidatedAction(action))
        case .toggleDrawer(let paneId):
            guard state.tabContaining(paneId: paneId) != nil else {
                return .failure(.paneNotFound(paneId: paneId, tabId: state.activeTabId ?? UUID()))
            }
            return .success(ValidatedAction(action))

        // System actions — trusted source, skip validation
        case .expireUndoEntry, .repair:
            return .success(ValidatedAction(action))
        }
    }

    /// Check that a tab exists and contains the given pane.
    private static func validateTabContainsPane(
        tabId: UUID, paneId: UUID, state: ActionStateSnapshot
    ) -> ActionValidationError? {
        guard let tab = state.tab(tabId) else {
            return .tabNotFound(tabId: tabId)
        }
        guard tab.paneIds.contains(paneId) else {
            return .paneNotFound(paneId: paneId, tabId: tabId)
        }
        return nil
    }

    /// Validate that a pane is not already present in any layout.
    /// Enforces invariant #3: each paneId at most once across all layouts.
    static func validatePaneCardinality(
        paneId: UUID,
        state: ActionStateSnapshot
    ) -> Result<Void, ActionValidationError> {
        if state.allPaneIds.contains(paneId) {
            return .failure(.paneAlreadyInLayout(paneId: paneId))
        }
        return .success(())
    }
}
