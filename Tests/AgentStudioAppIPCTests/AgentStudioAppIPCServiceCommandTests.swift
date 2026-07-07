import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio App IPC service command methods", .serialized)
struct AgentStudioAppIPCServiceCommandTests {
    @Test("command execution auth separates unsafe debug from automation and explicit UI presentation")
    func commandExecutionAuthSeparatesUnsafeDebugFromAutomationAndExplicitUIPresentation() async throws {
        let windowId = UUID()
        let commandId = IPCCommandIdentifier(rawValue: "showCommandBarCommands")
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            commandPort: FakeCommandPort(
                workspaceWindowId: windowId,
                activeScope: .commands,
                commands: [
                    IPCCommandListEntry(
                        id: commandId,
                        title: "Show Commands",
                        executionModes: [.headless],
                        targetKinds: [],
                        requiredPrivileges: []
                    )
                ]
            ),
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
        #expect(listResult.commands.map(\.id) == [commandId])

        let unsafeConnection = try await authenticatedConnection(
            fixture: fixture,
            kind: .unsafeDebugClient,
            requestId: 68
        )
        defer {
            unsafeConnection.connection.close()
        }
        let unsafeExecute = try await executeCommand(
            connection: unsafeConnection.connection,
            reader: unsafeConnection,
            requestId: 68,
            commandId: commandId
        )
        #expect(unsafeExecute.error?.code == -32_002)
        #expect(unsafeExecute.error?.message == "unauthorized")

        let automationConnection = try await authenticatedConnection(
            fixture: fixture,
            kind: .automationClient,
            requestId: 69,
            grantedScopes: [
                IPCPermissionScope(privilege: .appCommandExecute, target: .app, dataScope: .unspecified)
            ]
        )
        defer {
            automationConnection.connection.close()
        }
        let automationExecute = try await executeCommand(
            connection: automationConnection.connection,
            reader: automationConnection,
            requestId: 69,
            commandId: commandId
        )
        #expect(automationExecute.error?.code == -32_003)
        #expect(automationExecute.error?.message == "requires presentation")

        try sendRequest(
            connection: unsafeConnection.connection,
            request: JSONRPCClientRequest(
                id: .number(70),
                method: "ui.commandBar.open",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCCommandBarOpenParams(scope: .commands, correlationId: nil)
                )
            )
        )
        let open = try await unsafeConnection.receiveResponse()
        #expect(open.error == nil)
        let openResult = try decodeResponseResult(IPCCommandBarOpenResult.self, from: open)
        #expect(openResult.workspaceWindowId == windowId)
        #expect(openResult.scope == IPCCommandBarScope.commands)
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

private final class AuthenticatedIPCConnection {
    let connection: UnixSocketConnection
    var reader: TestFrameReader

    init(connection: UnixSocketConnection, reader: TestFrameReader) {
        self.connection = connection
        self.reader = reader
    }

    func receiveResponse() async throws -> JSONRPCResponseMessage {
        try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
    }
}

private func authenticatedConnection(
    fixture: LiveServerFixture,
    kind: IPCPrincipalKind,
    requestId: Int,
    grantedScopes: [IPCPermissionScope] = []
) async throws -> AuthenticatedIPCConnection {
    let principal = IPCPrincipal(
        principalId: UUID(),
        runtimeId: fixture.runtimeId,
        accessMode: .unsafeDebug,
        kind: kind,
        approvalAuthority: .noApprovalAuthority
    )
    for scope in grantedScopes {
        fixture.server.grantLedger.grant(scope, to: principal.principalId)
    }
    let token = try fixture.server.principalRegistry.issueSubjectToken(for: principal)
    let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
    var reader = TestFrameReader()
    try await loginWithoutBlockingMainActor(connection: connection, token: token, requestId: requestId, reader: &reader)
    return AuthenticatedIPCConnection(connection: connection, reader: reader)
}

private func executeCommand(
    connection: UnixSocketConnection,
    reader: AuthenticatedIPCConnection,
    requestId: Int,
    commandId: IPCCommandIdentifier
) async throws -> JSONRPCResponseMessage {
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(
            id: .number(requestId),
            method: "command.execute",
            params: try JSONRPCCodec.encodeJSONValue(
                IPCCommandExecuteParams(
                    commandId: commandId,
                    targetHandle: nil
                )
            )
        )
    )
    return try await reader.receiveResponse()
}
