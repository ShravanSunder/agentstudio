import Foundation
import Observation

enum ArrangementPanelPresentationPlacement: Equatable, Sendable {
    case tabBar
    case collapsedBar(paneId: UUID)
}

struct ArrangementPanelPresentationRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let tabId: UUID
    let workspaceWindowId: UUID
    let placement: ArrangementPanelPresentationPlacement

    init(
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

    func matches(
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
final class ArrangementPanelPresentationAtom {
    private(set) var pendingRequest: ArrangementPanelPresentationRequest?

    @discardableResult
    func present(
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

    func consume(_ request: ArrangementPanelPresentationRequest) {
        guard pendingRequest?.id == request.id else { return }
        pendingRequest = nil
    }
}
