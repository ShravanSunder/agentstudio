import Foundation

struct WorkspaceDrawerToggleRequest: Equatable, Sendable {
    let parentPaneID: UUID
}

enum WorkspaceDrawerToggleRejection: Equatable, Sendable {
    case parentPaneMissing(UUID)
    case paneIdentityMismatch(requestedPaneID: UUID, currentPaneID: UUID)
    case paneHasNoDrawer(UUID)
    case drawerParentMismatch(
        drawerID: UUID,
        expectedParentPaneID: UUID,
        actualParentPaneID: UUID
    )
}

enum WorkspaceDrawerCursorSelection: Equatable, Sendable {
    case collapsed
    case expanded(drawerID: UUID)

    init(expandedDrawerID: UUID?) {
        if let expandedDrawerID {
            self = .expanded(drawerID: expandedDrawerID)
        } else {
            self = .collapsed
        }
    }

    var expandedDrawerID: UUID? {
        switch self {
        case .collapsed:
            nil
        case .expanded(let drawerID):
            drawerID
        }
    }
}

struct WorkspaceDrawerToggleTransition: Equatable, Sendable {
    enum Operation: Equatable, Sendable {
        case expand(drawerID: UUID)
        case collapse(drawerID: UUID)
        case switchExpandedDrawer(fromDrawerID: UUID, toDrawerID: UUID)
    }

    let parentPaneID: UUID
    let operation: Operation
    let expectedCursor: WorkspaceDrawerCursorSelection
    let replacementCursor: WorkspaceDrawerCursorSelection

    fileprivate init(
        parentPaneID: UUID,
        operation: Operation,
        expectedCursor: WorkspaceDrawerCursorSelection,
        replacementCursor: WorkspaceDrawerCursorSelection
    ) {
        self.parentPaneID = parentPaneID
        self.operation = operation
        self.expectedCursor = expectedCursor
        self.replacementCursor = replacementCursor
    }
}

enum WorkspaceDrawerToggleDecision: Equatable, Sendable {
    case changed(WorkspaceDrawerToggleTransition)
    case rejected(WorkspaceDrawerToggleRejection)
}

enum WorkspaceDrawerToggleTransitionPlanner {
    static func plan(
        _ request: WorkspaceDrawerToggleRequest,
        currentPaneState: PaneGraphState?,
        currentExpandedDrawerID: UUID?
    ) -> WorkspaceDrawerToggleDecision {
        guard let currentPaneState else {
            return .rejected(.parentPaneMissing(request.parentPaneID))
        }
        guard currentPaneState.id == request.parentPaneID else {
            return .rejected(
                .paneIdentityMismatch(
                    requestedPaneID: request.parentPaneID,
                    currentPaneID: currentPaneState.id
                )
            )
        }
        guard let drawer = currentPaneState.drawer else {
            return .rejected(.paneHasNoDrawer(request.parentPaneID))
        }
        guard drawer.parentPaneId == request.parentPaneID else {
            return .rejected(
                .drawerParentMismatch(
                    drawerID: drawer.drawerId,
                    expectedParentPaneID: request.parentPaneID,
                    actualParentPaneID: drawer.parentPaneId
                )
            )
        }

        if currentExpandedDrawerID == drawer.drawerId {
            return .changed(
                WorkspaceDrawerToggleTransition(
                    parentPaneID: request.parentPaneID,
                    operation: .collapse(drawerID: drawer.drawerId),
                    expectedCursor: .expanded(drawerID: drawer.drawerId),
                    replacementCursor: .collapsed
                )
            )
        }
        if let currentExpandedDrawerID {
            return .changed(
                WorkspaceDrawerToggleTransition(
                    parentPaneID: request.parentPaneID,
                    operation: .switchExpandedDrawer(
                        fromDrawerID: currentExpandedDrawerID,
                        toDrawerID: drawer.drawerId
                    ),
                    expectedCursor: .expanded(drawerID: currentExpandedDrawerID),
                    replacementCursor: .expanded(drawerID: drawer.drawerId)
                )
            )
        }
        return .changed(
            WorkspaceDrawerToggleTransition(
                parentPaneID: request.parentPaneID,
                operation: .expand(drawerID: drawer.drawerId),
                expectedCursor: .collapsed,
                replacementCursor: .expanded(drawerID: drawer.drawerId)
            )
        )
    }
}
