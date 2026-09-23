import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

@MainActor
protocol AgentStudioIPCUIPresenting: AnyObject {
    func presentCommandBar(workspaceWindowId: UUID, scope: IPCCommandBarScope) throws -> IPCCommandBarOpenResult
    func presentArrangements(workspaceWindowId: UUID, contextPaneId: UUID?) throws -> IPCArrangementsOpenResult
}

@MainActor
struct AgentStudioIPCUIPresentationAdapter: AppIPCUIPresentationPort, @unchecked Sendable {
    private weak var presenter: (any AgentStudioIPCUIPresenting)?
    private let targetAuthorizer: any WorkspaceDurableTargetAuthorizing

    init(
        presenter: any AgentStudioIPCUIPresenting,
        targetAuthorizer: any WorkspaceDurableTargetAuthorizing
    ) {
        self.presenter = presenter
        self.targetAuthorizer = targetAuthorizer
    }

    func openCommandBar(_ params: IPCCommandBarOpenParams) throws -> IPCCommandBarOpenResult {
        guard let presenter else {
            throw AppIPCUIPresentationError(reason: .noActiveWindow)
        }
        let result = try presenter.presentCommandBar(workspaceWindowId: params.workspaceWindowId, scope: params.scope)
        return IPCCommandBarOpenResult(
            workspaceWindowId: result.workspaceWindowId,
            scope: result.scope,
            correlationId: params.correlationId
        )
    }

    func openArrangements(_ params: IPCArrangementsOpenParams) throws -> IPCArrangementsOpenResult {
        let contextPaneId = try durablePaneId(from: params.targetPaneHandle)
        guard let presenter else {
            throw AppIPCUIPresentationError(reason: .noActiveWindow)
        }
        let result = try presenter.presentArrangements(
            workspaceWindowId: params.workspaceWindowId, contextPaneId: contextPaneId)
        return IPCArrangementsOpenResult(
            workspaceWindowId: result.workspaceWindowId,
            tabId: result.tabId,
            contextPaneId: result.contextPaneId,
            correlationId: params.correlationId
        )
    }

    private func durablePaneId(from rawHandle: String?) throws -> UUID? {
        guard let rawHandle else { return nil }
        guard
            let handle = try? IPCHandle.parse(rawHandle),
            handle.kind == .pane,
            case .canonicalUUID(let paneId) = handle.reference,
            targetAuthorizer.containsPane(id: paneId)
        else {
            throw AppIPCUIPresentationError(reason: .targetNotFound)
        }
        return paneId
    }
}
