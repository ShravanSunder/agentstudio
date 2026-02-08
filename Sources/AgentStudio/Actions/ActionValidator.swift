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
            guard tab.paneCount > 1 else {
                return .failure(.singlePaneTab(tabId: tabId))
            }
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
        }
    }
}
