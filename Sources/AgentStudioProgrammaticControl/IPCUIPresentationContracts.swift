import Foundation

public struct IPCCommandBarOpenParams: Codable, Equatable, Sendable {
    public let scope: IPCCommandBarScope
    public let correlationId: UUID?

    public init(scope: IPCCommandBarScope, correlationId: UUID?) {
        self.scope = scope
        self.correlationId = correlationId
    }
}

public struct IPCCommandBarOpenResult: Codable, Equatable, Sendable {
    public let workspaceWindowId: UUID
    public let scope: IPCCommandBarScope
    public let correlationId: UUID?

    public init(workspaceWindowId: UUID, scope: IPCCommandBarScope, correlationId: UUID?) {
        self.workspaceWindowId = workspaceWindowId
        self.scope = scope
        self.correlationId = correlationId
    }
}

public struct IPCArrangementsOpenParams: Codable, Equatable, Sendable {
    public let targetPaneHandle: String?
    public let correlationId: UUID?

    public init(targetPaneHandle: String?, correlationId: UUID?) {
        self.targetPaneHandle = targetPaneHandle
        self.correlationId = correlationId
    }
}

public struct IPCArrangementsOpenResult: Codable, Equatable, Sendable {
    public let workspaceWindowId: UUID
    public let tabId: UUID
    public let contextPaneId: UUID?
    public let correlationId: UUID?

    public init(
        workspaceWindowId: UUID,
        tabId: UUID,
        contextPaneId: UUID?,
        correlationId: UUID?
    ) {
        self.workspaceWindowId = workspaceWindowId
        self.tabId = tabId
        self.contextPaneId = contextPaneId
        self.correlationId = correlationId
    }
}
