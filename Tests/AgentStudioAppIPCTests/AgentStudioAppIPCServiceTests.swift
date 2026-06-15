import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio App IPC service shell")
struct AgentStudioAppIPCServiceTests {
    @Test("composes service from configuration and protocol ports")
    func composesServiceFromConfigurationAndProtocolPorts() throws {
        let method = try IPCMethodDefinition(
            name: "system.identify",
            privilegeClasses: [.systemRead],
            executionOwner: .queryReader,
            resultSemantics: .applied
        )
        let runtimeId = UUID()
        let configuration = AgentStudioAppIPCConfiguration(
            runtimeId: runtimeId,
            accessMode: .agentStudioOnly,
            methodDefinitions: [method]
        )

        let service = AgentStudioAppIPCService(
            configuration: configuration,
            ports: AgentStudioAppIPCPorts(
                queryPort: FakeQueryPort(),
                layoutPort: FakeLayoutPort(),
                runtimePort: FakeRuntimePort(),
                permissionApprovalPort: FakePermissionApprovalPort()
            )
        )

        #expect(service.configuration.runtimeId == runtimeId)
        #expect(service.configuration.accessMode == .agentStudioOnly)
        #expect(service.configuration.methodDefinitions == [method])
    }
}

private struct FakeQueryPort: AppIPCQueryPort {}

private struct FakeLayoutPort: AppIPCLayoutPort {}

private struct FakeRuntimePort: AppIPCRuntimePort {}

private struct FakePermissionApprovalPort: AppIPCPermissionApprovalPort {
    func decision(for _: PermissionRecord, requester _: IPCPrincipal) -> ApprovalPolicyDecision {
        .ask
    }
}
