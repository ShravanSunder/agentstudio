import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

@MainActor
extension AppDelegate {
    func presentArrangements(workspaceWindowId: UUID, contextPaneId: UUID?) throws -> IPCArrangementsOpenResult {
        guard let controller = mainWindowController, controller.window != nil else {
            throw AppIPCUIPresentationError(reason: .noActiveWindow)
        }
        guard controller.workspaceWindowId == workspaceWindowId else {
            throw AppIPCUIPresentationError(reason: .targetNotFound)
        }
        guard let paneTabViewController = paneTabViewController() else {
            throw AppIPCUIPresentationError(reason: .noActiveWindow)
        }
        let presentation: ArrangementPanelProgrammaticPresentation
        switch paneTabViewController.presentArrangementPanel(contextPaneId: contextPaneId) {
        case .success(let successfulPresentation):
            presentation = successfulPresentation
        case .failure(let failure):
            let reason: AppIPCUIPresentationError.Reason =
                switch failure {
                case .noActiveWindow:
                    .noActiveWindow
                case .targetNotFound:
                    .targetNotFound
                case .validationRejected:
                    .validationRejected
                }
            throw AppIPCUIPresentationError(reason: reason)
        }

        return IPCArrangementsOpenResult(
            workspaceWindowId: presentation.workspaceWindowId,
            tabId: presentation.tabId,
            contextPaneId: presentation.contextPaneId,
            correlationId: nil
        )
    }
}
