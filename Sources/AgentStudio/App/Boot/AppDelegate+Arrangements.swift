import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

@MainActor
extension AppDelegate {
    func presentArrangements(contextPaneId: UUID?) throws -> IPCArrangementsOpenResult {
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
