import Foundation

enum DrawerCommandValidator {
    static func validateMembership(
        parentPaneId: UUID,
        drawerPaneId: UUID,
        state: ActionStateSnapshot
    ) -> ActionValidationError? {
        guard state.tabShowing(paneId: parentPaneId) != nil else {
            return .paneNotFound(paneId: parentPaneId, tabId: state.activeTabId ?? UUID())
        }
        guard state.drawerParentPaneId(of: drawerPaneId) == parentPaneId else {
            return .paneNotFound(paneId: drawerPaneId, tabId: state.activeTabId ?? UUID())
        }
        return nil
    }

    static func validateResultingLayout(
        _ resultingLayout: DrawerGridLayout,
        parentPaneId: UUID,
        state: ActionStateSnapshot,
        requestedDirection: SplitNewDirection,
        wouldCreateThirdRow: Bool
    ) -> Result<Void, ActionValidationError> {
        let rowCount = resultingLayout.bottomRow == nil ? 1 : 2
        guard rowCount <= 2, wouldCreateThirdRow == false else {
            return .failure(.invalidDrawerLayout(parentPaneId: parentPaneId))
        }

        return .success(())
    }

    static func validateInsertion(
        parentPaneId: UUID,
        targetDrawerPaneId: UUID,
        direction: SplitNewDirection,
        sizingMode: DropSizingMode,
        state: ActionStateSnapshot
    ) -> Result<Void, ActionValidationError> {
        guard state.tabShowing(paneId: parentPaneId) != nil else {
            return .failure(.paneNotFound(paneId: parentPaneId, tabId: state.activeTabId ?? UUID()))
        }
        guard state.drawerParentPaneId(of: targetDrawerPaneId) == parentPaneId else {
            return .failure(.paneNotFound(paneId: targetDrawerPaneId, tabId: state.activeTabId ?? UUID()))
        }
        guard let currentLayout = state.drawerLayout(for: parentPaneId) else {
            return .failure(.invalidDrawerLayout(parentPaneId: parentPaneId))
        }

        let projectedPaneId = UUID()
        guard
            let resultingLayout = currentLayout.inserting(
                paneId: projectedPaneId,
                at: targetDrawerPaneId,
                direction: direction,
                sizingMode: sizingMode
            )
        else {
            return .failure(.invalidDrawerLayout(parentPaneId: parentPaneId))
        }

        return validateResultingLayout(
            resultingLayout,
            parentPaneId: parentPaneId,
            state: state,
            requestedDirection: direction,
            wouldCreateThirdRow: false
        )
    }

    static func validateMove(
        parentPaneId: UUID,
        drawerPaneId: UUID,
        target: DrawerRearrangeTarget,
        sizingMode: DropSizingMode,
        state: ActionStateSnapshot
    ) -> Result<Void, ActionValidationError> {
        if let membershipError = validateMembership(
            parentPaneId: parentPaneId,
            drawerPaneId: drawerPaneId,
            state: state
        ) {
            return .failure(membershipError)
        }
        guard let currentLayout = state.drawerLayout(for: parentPaneId) else {
            return .failure(.invalidDrawerLayout(parentPaneId: parentPaneId))
        }
        guard
            currentLayout.projectedMove(
                paneId: drawerPaneId,
                target: target,
                sizingMode: sizingMode
            ) != nil
        else {
            return .failure(.invalidDrawerLayout(parentPaneId: parentPaneId))
        }
        return .success(())
    }
}
