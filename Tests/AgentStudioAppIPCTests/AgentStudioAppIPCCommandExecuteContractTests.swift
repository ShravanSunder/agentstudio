import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio App IPC typed command execution contracts")
struct AgentStudioAppIPCCommandExecuteContractTests {
    @Test("typed command request encodes exact identity correlation and argument fields")
    func typedRequestEncodesExactFields() throws {
        let commandId = IPCCommandIdentifier(rawValue: "fixtureCommand")
        let correlationId = UUIDv7.generate()
        let request = IPCCommandExecutionRequest(
            commandId: commandId,
            correlationId: correlationId,
            arguments: .noArguments
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]

        #expect(Set(object?.keys.map { $0 } ?? []) == ["arguments", "commandId", "correlationId"])
        #expect(object?["commandId"] as? String == commandId.rawValue)
        #expect(object?["correlationId"] as? String == correlationId.uuidString)
        #expect((object?["arguments"] as? [String: Any])?["kind"] as? String == "noArguments")
    }

    @Test("typed command schema rejects missing correlation before execution")
    func typedRequestRejectsMissingCorrelation() throws {
        let schema = try IPCCommandExecutionRequest.ipcSchema(allowing: [.noArguments])
        let data = Data(#"{"commandId":"fixtureCommand","arguments":{"kind":"noArguments"}}"#.utf8)

        #expect(throws: IPCSchemaValidationError.self) {
            _ = try schema.decode(IPCCommandExecutionRequest.self, from: data)
        }
    }

    @Test("typed command schema rejects an argument variant outside its descriptor")
    func typedRequestRejectsWrongArgumentVariant() throws {
        let request = IPCCommandExecutionRequest(
            commandId: IPCCommandIdentifier(rawValue: "fixtureCommand"),
            correlationId: UUIDv7.generate(),
            arguments: .repository(IPCRepositoryCommandArguments(repoId: UUIDv7.generate()))
        )
        let schema = try IPCCommandExecutionRequest.ipcSchema(allowing: [.noArguments])

        #expect(throws: IPCSchemaValidationError.self) {
            _ = try schema.decode(IPCCommandExecutionRequest.self, from: JSONEncoder().encode(request))
        }
    }

    @Test("unknown command identifiers remain open strings at the wire boundary")
    func unknownCommandIdentifierRemainsOpenString() throws {
        let request = IPCCommandExecutionRequest(
            commandId: IPCCommandIdentifier(rawValue: "futureCommand"),
            correlationId: UUIDv7.generate(),
            arguments: .noArguments
        )
        let schema = try IPCCommandExecutionRequest.ipcSchema(allowing: [.noArguments])

        let decoded = try schema.decode(
            IPCCommandExecutionRequest.self,
            from: JSONEncoder().encode(request)
        )
        #expect(decoded.commandId.rawValue == "futureCommand")
    }

    @Test("typed command result preserves command and correlation identity")
    func typedResultPreservesIdentity() throws {
        let commandId = IPCCommandIdentifier(rawValue: "fixtureCommand")
        let correlationId = UUIDv7.generate()
        let result = IPCCommandExecutionResult.applied(
            IPCCommandAppliedResult(commandId: commandId, correlationId: correlationId))
        let schema = try IPCCommandExecutionResult.ipcSchema(allowing: [.applied])

        let decoded = try schema.decode(
            IPCCommandExecutionResult.self,
            from: JSONEncoder().encode(result)
        )
        #expect(decoded == result)
        #expect(decoded.commandId == commandId)
        #expect(decoded.correlationId == correlationId)
    }
}
