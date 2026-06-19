import Foundation

public struct IPCCommandIdentifier: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum IPCCommandExecutionMode: String, Codable, Equatable, Sendable {
    case headless
    case uiPresentation
    case requiresInteractiveInput
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
    public let executionModes: [IPCCommandExecutionMode]
    public let targetKinds: [IPCHandleKind]
    public let requiredPrivileges: [IPCPrivilegeClass]

    public init(
        id: IPCCommandIdentifier,
        title: String,
        executionModes: [IPCCommandExecutionMode],
        targetKinds: [IPCHandleKind],
        requiredPrivileges: [IPCPrivilegeClass]
    ) {
        self.id = id
        self.title = title
        self.executionModes = executionModes
        self.targetKinds = targetKinds
        self.requiredPrivileges = requiredPrivileges
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

public struct IPCCommandExecuteResult: Codable, Equatable, Sendable {
    public let commandId: IPCCommandIdentifier
    public let applied: Bool
    public let targetHandle: String?

    public init(
        commandId: IPCCommandIdentifier,
        applied: Bool,
        targetHandle: String?
    ) {
        self.commandId = commandId
        self.applied = applied
        self.targetHandle = targetHandle
    }
}
