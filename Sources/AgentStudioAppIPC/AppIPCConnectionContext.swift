import AgentStudioProgrammaticControl
import Foundation

package struct AppIPCConnectionContext: Sendable {
    package let contextId: UUID
    package let channel: AgentStudioIPCChannel
    package let authenticatedContext: AgentStudioIPCAuthenticatedContext?
    package var principal: IPCPrincipal? { authenticatedContext?.principal }
    private let authenticateConnection: @Sendable (IPCAuthLoginParams) async throws -> IPCAuthStatusResult
    private let readAuthenticationStatus: @Sendable () -> IPCAuthStatusResult
    package let eventSubscriber: any IPCEventSubscriber

    package init(
        contextId: UUID,
        channel: AgentStudioIPCChannel,
        authenticatedContext: AgentStudioIPCAuthenticatedContext?,
        authenticate: @escaping @Sendable (IPCAuthLoginParams) async throws -> IPCAuthStatusResult,
        authenticationStatus: @escaping @Sendable () -> IPCAuthStatusResult,
        eventSubscriber: any IPCEventSubscriber
    ) {
        self.contextId = contextId
        self.channel = channel
        self.authenticatedContext = authenticatedContext
        self.authenticateConnection = authenticate
        self.readAuthenticationStatus = authenticationStatus
        self.eventSubscriber = eventSubscriber
    }

    package func authenticate(_ parameters: IPCAuthLoginParams) async throws -> IPCAuthStatusResult {
        try await authenticateConnection(parameters)
    }

    package func authenticationStatus() -> IPCAuthStatusResult {
        readAuthenticationStatus()
    }
}
