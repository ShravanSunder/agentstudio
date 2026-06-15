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

public struct IPCTerminalEventPayload: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let condition: IPCTerminalWaitCondition
    public let commandId: UUID?
    public let correlationId: UUID?
    public let exitCode: Int?
    public let duration: TimeInterval?
    public let healthy: Bool?

    public init(
        paneId: UUID,
        condition: IPCTerminalWaitCondition,
        commandId: UUID? = nil,
        correlationId: UUID? = nil,
        exitCode: Int? = nil,
        duration: TimeInterval? = nil,
        healthy: Bool? = nil
    ) {
        self.paneId = paneId
        self.condition = condition
        self.commandId = commandId
        self.correlationId = correlationId
        self.exitCode = exitCode
        self.duration = duration
        self.healthy = healthy
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

public enum IPCEventPayload: Codable, Equatable, Sendable {
    case permission(IPCPermissionEventPayload)
    case terminal(IPCTerminalEventPayload)

    private enum CodingKeys: String, CodingKey {
        case kind
        case permission
        case terminal
    }

    private enum Kind: String, Codable {
        case permission
        case terminal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .permission:
            self = .permission(try container.decode(IPCPermissionEventPayload.self, forKey: .permission))
        case .terminal:
            self = .terminal(try container.decode(IPCTerminalEventPayload.self, forKey: .terminal))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .permission(let payload):
            try container.encode(Kind.permission, forKey: .kind)
            try container.encode(payload, forKey: .permission)
        case .terminal(let payload):
            try container.encode(Kind.terminal, forKey: .kind)
            try container.encode(payload, forKey: .terminal)
        }
    }
}

public struct IPCEventNotification: Codable, Equatable, Sendable {
    public let eventId: UUID
    public let name: IPCEventName
    public let occurredAt: Date
    public let payload: IPCEventPayload

    public init(
        eventId: UUID,
        name: IPCEventName,
        occurredAt: Date,
        payload: IPCEventPayload
    ) {
        self.eventId = eventId
        self.name = name
        self.occurredAt = occurredAt
        self.payload = payload
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

    public var eventNotification: IPCEventNotification {
        IPCEventNotification(
            eventId: eventId,
            name: name,
            occurredAt: occurredAt,
            payload: .permission(payload)
        )
    }
}
