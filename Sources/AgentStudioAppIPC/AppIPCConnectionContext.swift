import AgentStudioProgrammaticControl
import Foundation

package struct AppIPCConnectionContext: Sendable {
    package let contextId: UUID
    package let channel: AgentStudioIPCChannel
    package let principal: IPCPrincipal?
    private let authenticateConnection: @Sendable (IPCAuthLoginParams) throws -> IPCAuthStatusResult
    private let readAuthenticationStatus: @Sendable () -> IPCAuthStatusResult
    package let eventSubscriber: any IPCEventSubscriber

    package init(
        contextId: UUID,
        channel: AgentStudioIPCChannel,
        principal: IPCPrincipal?,
        authenticate: @escaping @Sendable (IPCAuthLoginParams) throws -> IPCAuthStatusResult,
        authenticationStatus: @escaping @Sendable () -> IPCAuthStatusResult,
        eventSubscriber: any IPCEventSubscriber
    ) {
        self.contextId = contextId
        self.channel = channel
        self.principal = principal
        self.authenticateConnection = authenticate
        self.readAuthenticationStatus = authenticationStatus
        self.eventSubscriber = eventSubscriber
    }

    package func authenticate(_ parameters: IPCAuthLoginParams) throws -> IPCAuthStatusResult {
        try authenticateConnection(parameters)
    }

    package func authenticationStatus() -> IPCAuthStatusResult {
        readAuthenticationStatus()
    }
}
