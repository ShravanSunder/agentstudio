import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

@MainActor
extension AppDelegate {
    func presentArrangements(contextPaneId: UUID?) throws -> IPCArrangementsOpenResult {
        guard
            let workspaceWindowId = windowLifecycleStore.preferredWorkspaceWindowId,
            let presentation = paneTabViewController()?
                .presentArrangementPanel(contextPaneId: contextPaneId)
        else {
            throw AppIPCUIPresentationError(reason: .noActiveWindow)
        }

        return IPCArrangementsOpenResult(
            workspaceWindowId: workspaceWindowId,
            tabId: presentation.tabId,
            contextPaneId: presentation.contextPaneId,
            correlationId: nil
        )
    }
}
