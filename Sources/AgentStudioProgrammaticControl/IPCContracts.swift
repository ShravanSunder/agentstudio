import Foundation

public struct IPCPrincipal: Equatable, Sendable {
    public let principalId: UUID
    public let runtimeId: UUID
    public let accessMode: IPCAccessMode
    public let kind: IPCPrincipalKind
    public let approvalAuthority: IPCApprovalAuthority

    public init(
        principalId: UUID,
        runtimeId: UUID,
        accessMode: IPCAccessMode,
        kind: IPCPrincipalKind,
        approvalAuthority: IPCApprovalAuthority
    ) {
        self.principalId = principalId
        self.runtimeId = runtimeId
        self.accessMode = accessMode
        self.kind = kind
        self.approvalAuthority = approvalAuthority
    }
}

public enum IPCAccessMode: String, Codable, Equatable, Sendable {
    case off
    case agentStudioOnly
    case automationSameUser
    case password
    case unsafeDebug
}

public enum IPCPrincipalKind: Equatable, Sendable {
    case spawnedPaneAgent(boundPaneId: String, boundWorkspaceId: UUID?)
    case automationClient
    case futureMCPClient
    case unsafeDebugClient
}

public enum IPCApprovalAuthority: Equatable, Sendable {
    case noApprovalAuthority
    case policyConfigured(scopes: Set<IPCApprovalScope>)
    case delegatedApprover(scopes: Set<IPCApprovalScope>)
}

public struct IPCApprovalScope: Hashable, Sendable {
    public let privilege: IPCPrivilegeClass
    public let target: IPCTargetScope
    public let dataScope: IPCDataScope

    public init(privilege: IPCPrivilegeClass, target: IPCTargetScope, dataScope: IPCDataScope) {
        self.privilege = privilege
        self.target = target
        self.dataScope = dataScope
    }
}

public enum IPCTargetScope: Hashable, Sendable {
    case selfPane
    case pane(String)
    case workspace(UUID)
    case app
}

public enum IPCDataScope: String, Codable, CaseIterable, Hashable, Sendable {
    case unspecified
    case paneContext
    case terminalStatus
    case terminalSnapshot
    case terminalInput
    case terminalWait
    case permissionState
}

public enum IPCPrivilegeClass: String, Codable, CaseIterable, Hashable, Sendable {
    case systemRead
    case workspaceRead
    case paneContextRead
    case layoutMutate
    case terminalRead
    case terminalWrite
    case terminalStatusRead
    case terminalSnapshotRead
    case terminalInputWrite
    case terminalWait
    case eventsRead
    case permissionRequest
    case permissionRead
    case grantApprove
    case debugUnsafe
}

public enum IPCExecutionOwner: String, Codable, Equatable, Sendable {
    case appCommand
    case workspaceAction
    case runtimeCommand
    case queryReader
    case eventReader
    case permissionBroker
}

public enum IPCResultSemantics: String, Codable, Equatable, Sendable {
    case applied
    case accepted
}

public enum IPCPrincipalAvailability: String, Codable, Equatable, Sendable {
    case preAuthentication
    case authenticated
}

public struct IPCSchemaDescription: Equatable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct IPCMethodDefinition: Equatable, Sendable {
    public let name: String
    public let paramsSchema: IPCSchemaDescription
    public let resultSchema: IPCSchemaDescription
    public let privilegeClasses: Set<IPCPrivilegeClass>
    public let principalAvailability: IPCPrincipalAvailability
    public let executionOwner: IPCExecutionOwner
    public let resultSemantics: IPCResultSemantics

    public init(
        name: String,
        paramsSchema: IPCSchemaDescription = IPCSchemaDescription(name: "object"),
        resultSchema: IPCSchemaDescription = IPCSchemaDescription(name: "object"),
        privilegeClasses: Set<IPCPrivilegeClass>,
        principalAvailability: IPCPrincipalAvailability = .authenticated,
        executionOwner: IPCExecutionOwner,
        resultSemantics: IPCResultSemantics
    ) throws {
        let reservedBackendPrefix = ["z", "m", "x"].joined() + "."
        guard !name.hasPrefix(reservedBackendPrefix) else {
            throw IPCMethodDefinitionError.reservedBackendNamespaceNotAllowed
        }
        guard name.contains("."), !name.hasPrefix("."), !name.hasSuffix(".") else {
            throw IPCMethodDefinitionError.invalidMethodName
        }
        guard !privilegeClasses.isEmpty else {
            throw IPCMethodDefinitionError.missingPrivilegeClass
        }

        self.name = name
        self.paramsSchema = paramsSchema
        self.resultSchema = resultSchema
        self.privilegeClasses = privilegeClasses
        self.principalAvailability = principalAvailability
        self.executionOwner = executionOwner
        self.resultSemantics = resultSemantics
    }
}

public enum IPCMethodDefinitionError: Error, Equatable, Sendable {
    case invalidMethodName
    case missingPrivilegeClass
    case reservedBackendNamespaceNotAllowed
}

public enum IPCHandleKind: String, Codable, CaseIterable, Hashable, Sendable {
    case window
    case workspace
    case tab
    case pane
}

public enum IPCHandleReference: Hashable, Sendable {
    case friendlyOrdinal(Int)
    case canonicalUUID(UUID)
}

public struct IPCHandle: Hashable, Sendable {
    public let kind: IPCHandleKind
    public let reference: IPCHandleReference

    public init(kind: IPCHandleKind, reference: IPCHandleReference) {
        self.kind = kind
        self.reference = reference
    }

    public static func parse(_ rawValue: String) throws -> Self {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let kind = IPCHandleKind(rawValue: String(parts[0])) else {
            throw IPCHandleError.invalidHandle
        }

        let rawReference = String(parts[1])
        if let ordinal = Int(rawReference), ordinal > 0 {
            return Self(kind: kind, reference: .friendlyOrdinal(ordinal))
        }

        if let uuid = UUID(uuidString: rawReference) {
            return Self(kind: kind, reference: .canonicalUUID(uuid))
        }

        throw IPCHandleError.invalidHandle
    }
}

public enum IPCHandleError: Error, Equatable, Sendable {
    case invalidHandle
    case targetNotFound
}

public struct IPCPermissionScope: Hashable, Sendable {
    public let privilege: IPCPrivilegeClass
    public let target: IPCTargetScope
    public let dataScope: IPCDataScope

    public init(privilege: IPCPrivilegeClass, target: IPCTargetScope, dataScope: IPCDataScope) {
        self.privilege = privilege
        self.target = target
        self.dataScope = dataScope
    }
}

public enum IPCPermissionApprovalRoute: Hashable, Sendable {
    case appPolicy
    case humanPrompt
    case delegatedPrincipal(UUID)
}

public enum IPCPermissionRequestState: String, Codable, Equatable, Sendable {
    case pending
    case granted
    case denied
}

public struct IPCPermissionRequestParams: Equatable, Sendable {
    public let scope: IPCPermissionScope
    public let reason: String
    public let approvalRoute: IPCPermissionApprovalRoute

    public init(scope: IPCPermissionScope, reason: String, approvalRoute: IPCPermissionApprovalRoute) {
        self.scope = scope
        self.reason = reason
        self.approvalRoute = approvalRoute
    }
}

public struct IPCPermissionRequestResult: Equatable, Sendable {
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
