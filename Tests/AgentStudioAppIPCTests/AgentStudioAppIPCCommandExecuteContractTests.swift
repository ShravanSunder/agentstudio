import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio App IPC command execute contracts")
struct AgentStudioAppIPCCommandExecuteContractTests {
    @Test("unknown command ids decode and return unsupported capability")
    func unknownCommandIdsDecodeAndReturnUnsupportedCapability() throws {
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            commandPort: FakeCommandPort(workspaceWindowId: UUID(), activeScope: .commands)
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try sendRequest(
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
    func commandExecuteRejectsTargetHandleWithoutPublicTargetSemantics() throws {
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            commandPort: FakeCommandPort(workspaceWindowId: UUID(), activeScope: .commands)
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
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

        #expect(response.error?.code == -32_004)
        #expect(response.error?.message == "target not found")
    }
}
