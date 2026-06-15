import Foundation

public enum IPCEventName: String, Codable, CaseIterable, Equatable, Sendable {
    case permissionRequestCreated = "permission.requestCreated"
    case permissionRequestResolved = "permission.requestResolved"
    case permissionGrantRevoked = "permission.grantRevoked"
    case permissionGrantExpired = "permission.grantExpired"
    case terminalAttachReady = "terminal.attachReady"
    case terminalCommandFinished = "terminal.commandFinished"
    case terminalRendererHealthy = "terminal.rendererHealthy"
    case terminalTitleChanged = "terminal.titleChanged"
    case terminalCwdChanged = "terminal.cwdChanged"
    case terminalProgressChanged = "terminal.progressChanged"
}

public struct IPCEventSubscriptionResult: Codable, Equatable, Sendable {
    public let subscriptionId: UUID
    public let eventNames: [IPCEventName]

    public init(subscriptionId: UUID, eventNames: [IPCEventName]) {
        self.subscriptionId = subscriptionId
        self.eventNames = eventNames
    }
}

public struct IPCPermissionEventPayload: Codable, Equatable, Sendable {
    public let requestId: UUID
    public let state: IPCPermissionRequestState
    public let principalId: UUID
    public let requestedScope: IPCPermissionScope
    public let approvalRoute: IPCPermissionApprovalRoute

    public init(
        requestId: UUID,
        state: IPCPermissionRequestState,
        principalId: UUID,
        requestedScope: IPCPermissionScope,
        approvalRoute: IPCPermissionApprovalRoute
    ) {
        self.requestId = requestId
        self.state = state
        self.principalId = principalId
        self.requestedScope = requestedScope
        self.approvalRoute = approvalRoute
    }
}

public struct IPCPermissionEventNotification: Codable, Equatable, Sendable {
    public let eventId: UUID
    public let name: IPCEventName
    public let occurredAt: Date
    public let payload: IPCPermissionEventPayload

    public init(
        eventId: UUID,
        name: IPCEventName,
        occurredAt: Date,
        payload: IPCPermissionEventPayload
    ) {
        self.eventId = eventId
        self.name = name
        self.occurredAt = occurredAt
        self.payload = payload
    }
}
