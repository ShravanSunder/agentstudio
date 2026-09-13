import AgentStudioAppIPC
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio App IPC typed command port")
struct AgentStudioAppIPCServiceCommandTests {
    @Test("typed command preparation rejects unknown command identity without execution")
    @MainActor
    func preparationRejectsUnknownIdentityWithoutExecution() async throws {
        let port = FakeCommandPort()
        let request = IPCCommandExecutionRequest(
            commandId: IPCCommandIdentifier(rawValue: "futureCommand"),
            correlationId: UUIDv7.generate(),
            arguments: .noArguments
        )

        await #expect(throws: AppIPCCommandError.self) {
            try await port.prepareCommand(
                request,
                principal: diagnosticCommandPrincipal(),
                tools: unusedCommandTargetTools()
            )
        }
        #expect(port.receivedExecutionRequests.isEmpty)
    }

    @Test("typed command preparation rejects a wrong argument variant without execution")
    @MainActor
    func preparationRejectsWrongVariantWithoutExecution() async throws {
        let commandId = IPCCommandIdentifier(rawValue: "fixtureCommand")
        let correlationId = UUIDv7.generate()
        let result = IPCCommandExecutionResult.applied(
            IPCCommandAppliedResult(commandId: commandId, correlationId: correlationId))
        let descriptor = try makeFakeCommandDescriptor(
            FakeCommandDescriptorInput(
                id: commandId,
                executionMode: .headless,
                arguments: .noArguments,
                requiredPrivileges: [.appCommandExecute],
                dataScope: .unspecified,
                allowedTargetKinds: [],
                result: result
            )
        )
        let port = FakeCommandPort(commands: [descriptor])
        let request = IPCCommandExecutionRequest(
            commandId: commandId,
            correlationId: correlationId,
            arguments: .repository(IPCRepositoryCommandArguments(repoId: UUIDv7.generate()))
        )

        await #expect(throws: AppIPCCommandError.self) {
            try await port.prepareCommand(
                request,
                principal: diagnosticCommandPrincipal(),
                tools: unusedCommandTargetTools()
            )
        }
        #expect(port.receivedExecutionRequests.isEmpty)
    }

    @Test("typed command preparation preserves descriptor scopes and execution result")
    @MainActor
    func preparationPreservesScopesAndExecutionResult() async throws {
        let commandId = IPCCommandIdentifier(rawValue: "fixtureCommand")
        let correlationId = UUIDv7.generate()
        let result = IPCCommandExecutionResult.presented(
            IPCCommandPresentedResult(commandId: commandId, correlationId: correlationId))
        let descriptor = try makeFakeCommandDescriptor(
            FakeCommandDescriptorInput(
                id: commandId,
                executionMode: .uiPresentation,
                arguments: .noArguments,
                requiredPrivileges: [.uiPresent],
                dataScope: .uiSurface,
                allowedTargetKinds: [],
                result: result
            )
        )
        let port = FakeCommandPort(
            commands: [descriptor],
            executionResultsByCommandId: [commandId.rawValue: result],
            requiredPermissionTargetByPrivilege: [.uiPresent: .app]
        )
        let request = IPCCommandExecutionRequest(
            commandId: commandId,
            correlationId: correlationId,
            arguments: .noArguments
        )

        let prepared = try await port.prepareCommand(
            request,
            principal: diagnosticCommandPrincipal(),
            tools: unusedCommandTargetTools()
        )
        let executed = try await port.executeCommand(prepared.request)

        #expect(prepared.target == .app)
        #expect(
            prepared.requiredScopes
                == [IPCPermissionScope(privilege: .uiPresent, target: .app, dataScope: .uiSurface)]
        )
        #expect(executed == result)
        #expect(port.receivedExecutionRequests == [request])
    }
}

private func diagnosticCommandPrincipal() -> IPCPrincipal {
    IPCPrincipal(
        principalId: UUIDv7.generate(),
        runtimeId: UUIDv7.generate(),
        accessMode: .unsafeDebug,
        kind: .automationClient,
        approvalAuthority: .noApprovalAuthority
    )
}

private func unusedCommandTargetTools() -> AppIPCTargetResolutionTools {
    AppIPCTargetResolutionTools(canonicalizePaneHandle: { _ in
        throw AppIPCCommandError(reason: .targetNotFound)
    })
}
