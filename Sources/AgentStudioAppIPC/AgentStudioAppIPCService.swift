import AgentStudioProgrammaticControl
import Foundation

public protocol AppIPCQueryPort: Sendable {}

public protocol AppIPCLayoutPort: Sendable {}

public protocol AppIPCRuntimePort: Sendable {}

public protocol AppIPCPermissionApprovalPort: Sendable {
    func decision(for record: PermissionRecord, requester: IPCPrincipal) -> ApprovalPolicyDecision
}

public struct AgentStudioAppIPCPorts: Sendable {
    public let queryPort: any AppIPCQueryPort
    public let layoutPort: any AppIPCLayoutPort
    public let runtimePort: any AppIPCRuntimePort
    public let permissionApprovalPort: any AppIPCPermissionApprovalPort

    public init(
        queryPort: any AppIPCQueryPort,
        layoutPort: any AppIPCLayoutPort,
        runtimePort: any AppIPCRuntimePort,
        permissionApprovalPort: any AppIPCPermissionApprovalPort
    ) {
        self.queryPort = queryPort
        self.layoutPort = layoutPort
        self.runtimePort = runtimePort
        self.permissionApprovalPort = permissionApprovalPort
    }
}

public struct AgentStudioAppIPCConfiguration: Equatable, Sendable {
    public let runtimeId: UUID
    public let accessMode: IPCAccessMode
    public let methodDefinitions: [IPCMethodDefinition]

    public init(runtimeId: UUID, accessMode: IPCAccessMode, methodDefinitions: [IPCMethodDefinition]) {
        self.runtimeId = runtimeId
        self.accessMode = accessMode
        self.methodDefinitions = methodDefinitions
    }
}

public struct AgentStudioAppIPCService: Sendable {
    public let configuration: AgentStudioAppIPCConfiguration
    public let ports: AgentStudioAppIPCPorts

    public init(configuration: AgentStudioAppIPCConfiguration, ports: AgentStudioAppIPCPorts) {
        self.configuration = configuration
        self.ports = ports
    }
}
