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
