import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio App IPC service command methods", .serialized)
struct AgentStudioAppIPCServiceCommandTests {
    @Test("unsafe debug client can list commands and explicit UI presentation opens command bar")
    func unsafeDebugClientCanListCommandsAndExplicitUIPresentationOpensCommandBar() async throws {
        let windowId = UUID()
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            commandPort: FakeCommandPort(workspaceWindowId: windowId, activeScope: .commands),
            uiPresentationPort: FakeUIPresentationPort(workspaceWindowId: windowId)
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let list = try await sendRequestWithoutBlockingMainActor(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(id: .number(67), method: "command.list", params: .object([:]))
        )
        #expect(list.error == nil)
        let listResult = try decodeResponseResult(IPCCommandListResult.self, from: list)
        #expect(listResult.commands.isEmpty)

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
        try await loginWithoutBlockingMainActor(connection: connection, token: token, requestId: 68, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(68),
                method: "command.execute",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCCommandExecuteParams(
                        commandId: IPCCommandIdentifier(rawValue: "showCommandBarCommands"),
                        targetHandle: nil
                    )
                )
            )
        )
        let execute = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
        #expect(execute.error?.code == -32_003)
        #expect(execute.error?.message == "requires presentation")

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(69),
                method: "ui.commandBar.open",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCCommandBarOpenParams(scope: .commands, correlationId: nil)
                )
            )
        )
        let open = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
        #expect(open.error == nil)
        let openResult = try decodeResponseResult(IPCCommandBarOpenResult.self, from: open)
        #expect(openResult.workspaceWindowId == windowId)
        #expect(openResult.scope == .commands)
    }

    @Test("spawned pane agents cannot execute command methods")
    func spawnedPaneAgentsCannotExecuteCommandMethods() async throws {
        let fixture = try LiveServerFixture(
            commandPort: FakeCommandPort(workspaceWindowId: UUID(), activeScope: .commands)
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()
        let principal = IPCPrincipal(
            principalId: UUID(),
            runtimeId: fixture.runtimeId,
            accessMode: .agentStudioOnly,
            kind: .spawnedPaneAgent(boundPaneId: fixture.boundPaneId.uuidString, boundWorkspaceId: nil),
            approvalAuthority: .noApprovalAuthority
        )
        let token = try fixture.server.principalRegistry.issueSubjectToken(for: principal)
        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        defer {
            connection.close()
        }
        var reader = TestFrameReader()
        try await loginWithoutBlockingMainActor(connection: connection, token: token, requestId: 69, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(70),
                method: "command.execute",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCCommandExecuteParams(
                        commandId: IPCCommandIdentifier(rawValue: "showCommandBarCommands"),
                        targetHandle: nil
                    )
                )
            )
        )
        let execute = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
        #expect(execute.error?.code == -32_002)
        #expect(execute.error?.message == "unauthorized")
    }
}
