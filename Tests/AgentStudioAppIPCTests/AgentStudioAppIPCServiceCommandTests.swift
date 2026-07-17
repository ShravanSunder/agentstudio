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
                        executionModes: [.uiPresentation],
                        targetKinds: [],
                        requiredPrivileges: [.uiPresent]
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
        #expect(listResult.commands.first?.executionModes == [.uiPresentation])
        #expect(listResult.commands.first?.requiredPrivileges == [.uiPresent])

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
            requestId: 69,
            commandId: commandId
        )
        #expect(unsafeExecute.error?.code == -32_002)
        #expect(unsafeExecute.error?.message == "unauthorized")

        let automationConnection = try await authenticatedConnection(
            fixture: fixture,
            kind: .automationClient,
            requestId: 70
        )
        defer {
            automationConnection.connection.close()
        }
        let automationWithoutUIPresentExecute = try await executeCommand(
            connection: automationConnection.connection,
            reader: automationConnection,
            requestId: 71,
            commandId: commandId
        )
        #expect(automationWithoutUIPresentExecute.error?.code == -32_002)
        #expect(automationWithoutUIPresentExecute.error?.message == "unauthorized")

        let presentationConnection = try await authenticatedConnection(
            fixture: fixture,
            kind: .automationClient,
            requestId: 72,
            grantedScopes: [
                IPCPermissionScope(privilege: .appCommandExecute, target: .app, dataScope: .unspecified),
                IPCPermissionScope(privilege: .uiPresent, target: .app, dataScope: .uiSurface),
            ]
        )
        defer {
            presentationConnection.connection.close()
        }
        let presentationExecute = try await executeCommand(
            connection: presentationConnection.connection,
            reader: presentationConnection,
            requestId: 73,
            commandId: commandId
        )
        #expect(presentationExecute.error?.code == -32_003)
        #expect(presentationExecute.error?.message == "requires presentation")

        try sendRequest(
            connection: unsafeConnection.connection,
            request: JSONRPCClientRequest(
                id: .number(74),
                method: "ui.commandBar.open",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCCommandBarOpenParams(scope: .commands, correlationId: nil)
                )
            )
        )
        let open = try await unsafeConnection.receiveResponse(expectedRequestId: 74)
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

    func receiveResponse(expectedRequestId: Int) async throws -> JSONRPCResponseMessage {
        let response = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
        #expect(response.id == .number(expectedRequestId))
        return response
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
    return try await reader.receiveResponse(expectedRequestId: requestId)
}
