import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio App IPC service auth modes", .serialized)
struct AgentStudioAppIPCServiceAuthModeTests {
    @Test("authenticated diagnostic credential invokes a debug-testing method")
    func authenticatedDiagnosticInvokesDebugTestingMethod() throws {
        let workspaceWindowId = UUIDv7.generate()
        let correlationId = UUIDv7.generate()
        let fixture = try LiveServerFixture(
            channel: .debug,
            uiPresentationPort: FakeUIPresentationPort(workspaceWindowId: workspaceWindowId)
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()
        let token = try fixture.issueTestCredential(
            for: .diagnostic(generationId: UUIDv7.generate(), status: .active)
        )
        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path)
        )
        defer {
            connection.close()
        }
        var reader = TestFrameReader()

        try login(connection: connection, token: token, requestId: 10, reader: &reader)
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(11),
                method: "ui.commandBar.open",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCCommandBarOpenParams(
                        workspaceWindowId: workspaceWindowId,
                        scope: .commands,
                        correlationId: correlationId
                    )
                )
            )
        )
        let response = try reader.receiveResponse(connection: connection)
        let result = try decodeResponseResult(IPCCommandBarOpenResult.self, from: response)

        #expect(response.error == nil)
        #expect(result.workspaceWindowId == workspaceWindowId)
        #expect(result.scope == .commands)
        #expect(result.correlationId == correlationId)
    }

    @Test("debug server requires an explicit diagnostic credential")
    func debugServerRequiresExplicitDiagnosticCredential() throws {
        let fixture = try LiveServerFixture(channel: .debug)
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(1), method: "auth.login",
                params: .object([
                    "token": .string("unregistered-diagnostic-token")
                ]))
        )
        #expect(response.error?.code == -32_001)
    }

    @Test("non-debug server channels do not admit diagnostic credentials")
    func nonDebugServerChannelsDoNotAdmitDiagnosticCredentials() throws {
        for channel in [AgentStudioIPCChannel.stable, .beta] {
            let fixture = try LiveServerFixture(channel: channel)
            defer {
                fixture.cleanup()
            }
            try fixture.server.start()
            let token = try fixture.issueTestCredential(
                for: .diagnostic(generationId: UUIDv7.generate(), status: .active)
            )

            let response = try sendRequest(
                socketPath: fixture.paths.socketURL.path,
                request: JSONRPCClientRequest(
                    id: .number(2), method: "auth.login",
                    params: .object([
                        "token": .string(token.rawValue)
                    ]))
            )
            #expect(response.error?.code == -32_001)
        }
    }
}
