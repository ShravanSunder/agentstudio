import Foundation
import Observation

package enum ArrangementPanelPresentationPlacement: Equatable, Sendable {
    case tabBar
    case collapsedBar(paneId: UUID)
}

package struct ArrangementPanelPresentationRequest: Equatable, Identifiable, Sendable {
    package let id: UUID
    package let tabId: UUID
    package let workspaceWindowId: UUID
    package let placement: ArrangementPanelPresentationPlacement

    package init(
        id: UUID = UUID(),
        tabId: UUID,
        workspaceWindowId: UUID,
        placement: ArrangementPanelPresentationPlacement = .tabBar
    ) {
        self.id = id
        self.tabId = tabId
        self.workspaceWindowId = workspaceWindowId
        self.placement = placement
    }

    package func matches(
        tabId: UUID,
        workspaceWindowId: UUID,
        placement: ArrangementPanelPresentationPlacement
    ) -> Bool {
        self.tabId == tabId
            && self.workspaceWindowId == workspaceWindowId
            && self.placement == placement
    }
}

@MainActor
@Observable
package final class ArrangementPanelPresentationAtom {
    package private(set) var pendingRequest: ArrangementPanelPresentationRequest?

    @discardableResult
    package func present(
        tabId: UUID,
        workspaceWindowId: UUID,
        placement: ArrangementPanelPresentationPlacement = .tabBar
    ) -> ArrangementPanelPresentationRequest {
        let request = ArrangementPanelPresentationRequest(
            tabId: tabId,
            workspaceWindowId: workspaceWindowId,
            placement: placement
        )
        pendingRequest = request
        return request
    }

    package func consume(_ request: ArrangementPanelPresentationRequest) {
        guard pendingRequest?.id == request.id else { return }
        pendingRequest = nil
    }
}
