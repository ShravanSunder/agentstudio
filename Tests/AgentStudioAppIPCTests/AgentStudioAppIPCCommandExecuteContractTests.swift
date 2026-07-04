import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio App IPC command execute contracts")
struct AgentStudioAppIPCCommandExecuteContractTests {
    @Test("command execute params encode exact public keys and default omitted arguments")
    func commandExecuteParamsEncodeExactPublicKeysAndDefaultOmittedArguments() throws {
        let decoded = try JSONDecoder().decode(
            IPCCommandExecuteParams.self,
            from: Data(#"{"commandId":"setRepoSidebarVisibilityMode"}"#.utf8)
        )
        #expect(decoded.commandId == IPCCommandIdentifier(rawValue: "setRepoSidebarVisibilityMode"))
        #expect(decoded.targetHandle == nil)
        #expect(decoded.arguments.isEmpty)

        let encodedData = try JSONEncoder().encode(
            IPCCommandExecuteParams(
                commandId: IPCCommandIdentifier(rawValue: "setRepoSidebarVisibilityMode"),
                targetHandle: nil,
                arguments: ["mode": "favoritesOnly"]
            )
        )
        let encodedObject = try #require(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])

        #expect(Set(encodedObject.keys) == ["commandId", "targetHandle", "arguments"])
        #expect(encodedObject["commandId"] as? String == "setRepoSidebarVisibilityMode")
        #expect(encodedObject["targetHandle"] is NSNull)
        let arguments = try #require(encodedObject["arguments"] as? [String: String])
        #expect(arguments == ["mode": "favoritesOnly"])
    }

    @Test("command list entry argument schema encodes stable string enum shape")
    func commandListEntryArgumentSchemaEncodesStableStringEnumShape() throws {
        let entry = IPCCommandListEntry(
            id: IPCCommandIdentifier(rawValue: "setRepoSidebarVisibilityMode"),
            title: "Set Repo Sidebar Visibility Mode",
            executionModes: [.headless],
            targetKinds: [],
            requiredPrivileges: [.layoutMutate],
            argumentSchema: [
                IPCCommandArgumentSchema(
                    name: "mode",
                    kind: .stringEnum(values: ["all", "favoritesOnly"]),
                    isRequired: true
                )
            ]
        )

        let encodedData = try JSONEncoder().encode(entry)
        let encodedObject = try #require(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])

        #expect(
            Set(encodedObject.keys) == [
                "id",
                "title",
                "executionModes",
                "targetKinds",
                "requiredPrivileges",
                "argumentSchema",
            ])
        let argumentSchema = try #require(encodedObject["argumentSchema"] as? [[String: Any]])
        let modeArgument = try #require(argumentSchema.first)
        #expect(modeArgument["name"] as? String == "mode")
        #expect(modeArgument["isRequired"] as? Bool == true)
        let kind = try #require(modeArgument["kind"] as? [String: Any])
        #expect(kind["type"] as? String == "stringEnum")
        #expect(kind["values"] as? [String] == ["all", "favoritesOnly"])
    }

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

    @Test("command execute accepts argument payload and returns command success")
    func commandExecuteAcceptsArgumentPayloadAndReturnsCommandSuccess() async throws {
        let commandPort = FakeCommandPort(
            workspaceWindowId: UUID(),
            activeScope: .commands,
            successfulCommandId: "setRepoSidebarVisibilityMode"
        )
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            commandPort: commandPort
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try await sendRequestWithoutBlockingMainActor(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(72),
                method: "command.execute",
                params: .object([
                    "commandId": .string("setRepoSidebarVisibilityMode"),
                    "arguments": .object(["mode": .string("favoritesOnly")]),
                ])
            )
        )

        #expect(response.error == nil)
        let result = try decodeResponseResult(IPCCommandExecuteResult.self, from: response)
        #expect(result.commandId == IPCCommandIdentifier(rawValue: "setRepoSidebarVisibilityMode"))
        #expect(result.applied)
        #expect(commandPort.receivedExecuteParams.map(\.arguments) == [["mode": "favoritesOnly"]])
    }

    @Test("command execute rejects wrong typed argument values as validation rejected")
    func commandExecuteRejectsWrongTypedArgumentValuesAsValidationRejected() async throws {
        let commandPort = FakeCommandPort(
            workspaceWindowId: UUID(),
            activeScope: .commands,
            successfulCommandId: "setRepoSidebarVisibilityMode"
        )
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            commandPort: commandPort
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try await sendRequestWithoutBlockingMainActor(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(74),
                method: "command.execute",
                params: .object([
                    "commandId": .string("setRepoSidebarVisibilityMode"),
                    "arguments": .object(["mode": .number(1)]),
                ])
            )
        )

        #expect(response.error?.code == -32_007)
        #expect(response.error?.message == "validation rejected")
        #expect(commandPort.receivedExecuteParams.count == 1)
        #expect(commandPort.receivedExecuteParams.first?.arguments.isEmpty == true)
        #expect(commandPort.receivedExecuteParams.first?.argumentsContainOnlyStrings == false)
    }

    @Test("command execute maps valid command unavailable state to stable error")
    func commandExecuteMapsValidCommandUnavailableStateToStableError() async throws {
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            commandPort: FakeCommandPort(
                workspaceWindowId: UUID(),
                activeScope: .commands,
                stateUnavailableCommandId: "setRepoSidebarVisibilityMode"
            )
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try await sendRequestWithoutBlockingMainActor(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(73),
                method: "command.execute",
                params: .object([
                    "commandId": .string("setRepoSidebarVisibilityMode"),
                    "arguments": .object(["mode": .string("favoritesOnly")]),
                ])
            )
        )

        #expect(response.error?.code == -32_005)
        #expect(response.error?.message == "state unavailable")
    }
}
