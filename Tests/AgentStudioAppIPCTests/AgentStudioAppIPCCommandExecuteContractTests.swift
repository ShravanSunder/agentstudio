import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio App IPC command execute contracts")
struct AgentStudioAppIPCCommandExecuteContractTests {
    @Test("unknown command ids decode and return unsupported capability")
    func unknownCommandIdsDecodeAndReturnUnsupportedCapability() async throws {
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            commandPort: FakeCommandPort(workspaceWindowId: UUID(), activeScope: .commands)
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try await sendRequestWithoutBlockingMainActor(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(70),
                method: "command.execute",
                params: .object(["commandId": .string("futureCommand")])
            )
        )

        #expect(response.error?.code == -32_003)
        #expect(response.error?.message == "unsupported capability")
    }

    @Test("command execute rejects target handle without public target semantics")
    func commandExecuteRejectsTargetHandleWithoutPublicTargetSemantics() async throws {
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            commandPort: FakeCommandPort(workspaceWindowId: UUID(), activeScope: .commands)
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()
        let principal = IPCPrincipal(
            principalId: UUID(),
            runtimeId: fixture.runtimeId,
            accessMode: .unsafeDebug,
            kind: .unsafeDebugClient,
            approvalAuthority: .noApprovalAuthority
        )
        let token = try fixture.server.principalRegistry.issueSubjectToken(for: principal)
        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        defer {
            connection.close()
        }
        var reader = TestFrameReader()
        try await loginWithoutBlockingMainActor(connection: connection, token: token, requestId: 70, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(71),
                method: "command.execute",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCCommandExecuteParams(
                        commandId: IPCCommandIdentifier(rawValue: "futureCommand"),
                        targetHandle: "pane:1"
                    )
                )
            )
        )
        let response = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)

        #expect(response.error?.code == -32_004)
        #expect(response.error?.message == "target not found")
    }
}
