import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

@MainActor
protocol AgentStudioIPCUIPresenting: AnyObject {
    func presentCommandBar(scope: IPCCommandBarScope) throws -> IPCCommandBarOpenResult
}

@MainActor
struct AgentStudioIPCUIPresentationAdapter: AppIPCUIPresentationPort, @unchecked Sendable {
    private let presenter: any AgentStudioIPCUIPresenting

    init(presenter: any AgentStudioIPCUIPresenting) {
        self.presenter = presenter
    }

    func openCommandBar(_ params: IPCCommandBarOpenParams) throws -> IPCCommandBarOpenResult {
        let result = try presenter.presentCommandBar(scope: params.scope)
        return IPCCommandBarOpenResult(
            workspaceWindowId: result.workspaceWindowId,
            scope: result.scope,
            correlationId: params.correlationId
        )
    }
}
