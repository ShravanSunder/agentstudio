import Foundation

public enum IPCCommandIdentifier: String, Codable, CaseIterable, Equatable, Sendable {
    case quickFind
    case commandPalette
    case panePicker
    case repoWorktreePicker
}

public enum IPCCommandBarScope: String, Codable, Equatable, Sendable {
    case everything
    case commands
    case panes
    case repos
}

public struct IPCCommandListEntry: Codable, Equatable, Sendable {
    public let id: IPCCommandIdentifier
    public let title: String

    public init(id: IPCCommandIdentifier, title: String) {
        self.id = id
        self.title = title
    }
}

public struct IPCCommandListResult: Codable, Equatable, Sendable {
    public let commands: [IPCCommandListEntry]

    public init(commands: [IPCCommandListEntry]) {
        self.commands = commands
    }
}

public struct IPCCommandExecuteParams: Codable, Equatable, Sendable {
    public let commandId: IPCCommandIdentifier
    public let targetHandle: String?

    public init(commandId: IPCCommandIdentifier, targetHandle: String?) {
        self.commandId = commandId
        self.targetHandle = targetHandle
    }
}

public struct IPCCommandBarPostcondition: Codable, Equatable, Sendable {
    public let workspaceWindowId: UUID
    public let scope: IPCCommandBarScope

    public init(workspaceWindowId: UUID, scope: IPCCommandBarScope) {
        self.workspaceWindowId = workspaceWindowId
        self.scope = scope
    }
}

public struct IPCCommandExecuteResult: Codable, Equatable, Sendable {
    public let commandId: IPCCommandIdentifier
    public let applied: Bool
    public let workspaceWindowId: UUID
    public let commandBar: IPCCommandBarPostcondition?

    public init(
        commandId: IPCCommandIdentifier,
        applied: Bool,
        workspaceWindowId: UUID,
        commandBar: IPCCommandBarPostcondition?
    ) {
        self.commandId = commandId
        self.applied = applied
        self.workspaceWindowId = workspaceWindowId
        self.commandBar = commandBar
    }
}
