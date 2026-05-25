import Foundation
import Observation

struct ArrangementPanelPresentationRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let tabId: UUID
    let workspaceWindowId: UUID?

    init(id: UUID = UUID(), tabId: UUID, workspaceWindowId: UUID?) {
        self.id = id
        self.tabId = tabId
        self.workspaceWindowId = workspaceWindowId
    }
}

@MainActor
@Observable
final class ArrangementPanelPresentationAtom {
    private(set) var pendingRequest: ArrangementPanelPresentationRequest?

    @discardableResult
    func present(tabId: UUID, workspaceWindowId: UUID?) -> ArrangementPanelPresentationRequest {
        let request = ArrangementPanelPresentationRequest(
            tabId: tabId,
            workspaceWindowId: workspaceWindowId
        )
        pendingRequest = request
        return request
    }

    func consume(_ request: ArrangementPanelPresentationRequest) {
        guard pendingRequest?.id == request.id else { return }
        pendingRequest = nil
    }
}
