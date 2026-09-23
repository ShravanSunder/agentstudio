import AgentStudioProgrammaticControl
import Foundation

/// A1 admission for a pane-bound agent calling a method that declares an
/// eligibility: the eligibility, then own-pane membership of every resolved
/// target, then the argument rules. It stands in for the privilege baseline
/// and grant ledger for those methods.
struct AppIPCPaneAgentAuthorization: Sendable {
    let methodRegistry: AppIPCMethodRegistry
    let ownPaneScopePort: any AppIPCOwnPaneScopePort

    func authorize(
        boundPaneId: String,
        methodEligibility: IPCAgentEligibility,
        request: AppIPCMethodAuthorizationRequest
    ) async throws {
        let refusedName = request.commandId ?? request.methodName
        switch effectiveEligibility(methodEligibility, request: request) {
        case .notYetAllowed:
            throw AuthorizationError.notYetAllowed(refusedName)
        case .anyTarget:
            return
        case .ownPane:
            guard let boundId = UUID(uuidString: boundPaneId),
                let scope = await ownPaneScopePort.ownPaneScope(boundPaneId: boundId),
                !request.resolvedPaneIds.isEmpty,
                request.resolvedPaneIds.allSatisfy({ scope.membership(of: $0) != .outside })
            else {
                throw AuthorizationError.notYetAllowed(refusedName)
            }
            try Self.checkArgumentRule(request.agentArgumentRule, scope: scope, refusedName: refusedName)
        }
    }

    /// `command.execute` carries the pane-scoped class; each command's own
    /// eligibility decides.
    private func effectiveEligibility(
        _ methodEligibility: IPCAgentEligibility,
        request: AppIPCMethodAuthorizationRequest
    ) -> IPCAgentEligibility {
        guard request.methodName == AppIPCMethodNames.commandExecute else { return methodEligibility }
        guard let commandId = request.commandId else { return .notYetAllowed }
        return methodRegistry.commandAgentEligibility(commandId)
    }

    static func checkArgumentRule(
        _ rule: AppIPCAgentArgumentRule,
        scope: AppIPCOwnPaneScope,
        refusedName: String
    ) throws {
        switch rule {
        case .targetOnly:
            return
        case .closesPane(let paneId):
            guard paneId != scope.boundPaneId else {
                throw AuthorizationError.refusedForAgent(refusedName)
            }
        case .addsDrawerChild(let parentPaneId):
            guard !scope.isDrawerTerminal, parentPaneId == scope.boundPaneId else {
                throw AuthorizationError.refusedForAgent(refusedName)
            }
        }
    }
}
