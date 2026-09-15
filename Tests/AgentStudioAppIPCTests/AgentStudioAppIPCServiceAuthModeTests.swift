import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import Foundation
import Testing

@Suite("AgentStudio App IPC service auth modes", .serialized)
struct AgentStudioAppIPCServiceAuthModeTests {
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
