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

private struct FakeQueryPort: AppIPCQueryPort {
    func systemIdentify() throws -> IPCSystemIdentifyResult {
        IPCSystemIdentifyResult(runtimeId: UUID(), accessMode: .agentStudioOnly, appVersion: "test")
    }

    func systemVersion() throws -> IPCSystemVersionResult {
        IPCSystemVersionResult(appVersion: "test")
    }

    func systemCapabilities() throws -> IPCSystemCapabilitiesResult {
        IPCSystemCapabilitiesResult(methods: [])
    }

    func listWindows() throws -> IPCWindowListResult {
        IPCWindowListResult(windows: [])
    }

    func currentWindow() throws -> IPCCurrentWindowResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func listWorkspaces() throws -> IPCWorkspaceListResult {
        IPCWorkspaceListResult(workspaces: [])
    }

    func currentWorkspace() throws -> IPCCurrentWorkspaceResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func listPanes() throws -> IPCPaneListResult {
        IPCPaneListResult(panes: [])
    }

    func currentPane() throws -> IPCPaneSnapshotResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func snapshotPane(_: UUID) throws -> IPCPaneSnapshotResult {
        throw AppIPCQueryError(reason: .targetNotFound)
    }
}

private struct FakeLayoutPort: AppIPCLayoutPort {}

private struct FakeRuntimePort: AppIPCRuntimePort {}

private struct FakePermissionApprovalPort: AppIPCPermissionApprovalPort {
    func decision(for _: PermissionRecord, requester _: IPCPrincipal) -> ApprovalPolicyDecision {
        .ask
    }
}
