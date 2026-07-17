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

public enum IPCCommandArgumentKind: Equatable, Sendable {
    case stringEnum(values: [String])

    private enum CodingKeys: String, CodingKey {
        case type
        case values
    }

    private enum KindType: String, Codable {
        case stringEnum
    }
}

extension IPCCommandArgumentKind: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindType.self, forKey: .type)
        switch type {
        case .stringEnum:
            self = .stringEnum(values: try container.decode([String].self, forKey: .values))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stringEnum(let values):
            try container.encode(KindType.stringEnum, forKey: .type)
            try container.encode(values, forKey: .values)
        }
    }
}

public struct IPCCommandArgumentSchema: Codable, Equatable, Sendable {
    public let name: String
    public let kind: IPCCommandArgumentKind
    public let isRequired: Bool

    public init(
        name: String,
        kind: IPCCommandArgumentKind,
        isRequired: Bool
    ) {
        self.name = name
        self.kind = kind
        self.isRequired = isRequired
    }
}

public struct IPCCommandListEntry: Codable, Equatable, Sendable {
    public let id: IPCCommandIdentifier
    public let title: String
    public let executionModes: [IPCCommandExecutionMode]
    public let targetKinds: [IPCHandleKind]
    public let requiredPrivileges: [IPCPrivilegeClass]
    public let argumentSchema: [IPCCommandArgumentSchema]

    public init(
        id: IPCCommandIdentifier,
        title: String,
        executionModes: [IPCCommandExecutionMode],
        targetKinds: [IPCHandleKind],
        requiredPrivileges: [IPCPrivilegeClass],
        argumentSchema: [IPCCommandArgumentSchema] = []
    ) {
        self.id = id
        self.title = title
        self.executionModes = executionModes
        self.targetKinds = targetKinds
        self.requiredPrivileges = requiredPrivileges
        self.argumentSchema = argumentSchema
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
    public let arguments: [String: String]
    public let argumentsContainOnlyStrings: Bool

    public init(
        commandId: IPCCommandIdentifier,
        targetHandle: String?,
        arguments: [String: String] = [:]
    ) {
        self.commandId = commandId
        self.targetHandle = targetHandle
        self.arguments = arguments
        self.argumentsContainOnlyStrings = true
    }

    private enum CodingKeys: String, CodingKey {
        case commandId
        case targetHandle
        case arguments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commandId = try container.decode(IPCCommandIdentifier.self, forKey: .commandId)
        targetHandle = try container.decodeIfPresent(String.self, forKey: .targetHandle)
        do {
            arguments = try container.decodeIfPresent([String: String].self, forKey: .arguments) ?? [:]
            argumentsContainOnlyStrings = true
        } catch {
            arguments = [:]
            argumentsContainOnlyStrings = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(commandId, forKey: .commandId)
        if let targetHandle {
            try container.encode(targetHandle, forKey: .targetHandle)
        } else {
            try container.encodeNil(forKey: .targetHandle)
        }
        try container.encode(arguments, forKey: .arguments)
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
