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
            from: Data(#"{"commandId":"setRepoSidebarSortOrder"}"#.utf8)
        )
        #expect(decoded.commandId == IPCCommandIdentifier(rawValue: "setRepoSidebarSortOrder"))
        #expect(decoded.targetHandle == nil)
        #expect(decoded.arguments.isEmpty)

        let encodedData = try JSONEncoder().encode(
            IPCCommandExecuteParams(
                commandId: IPCCommandIdentifier(rawValue: "setRepoSidebarSortOrder"),
                targetHandle: nil,
                arguments: ["order": "descending"]
            )
        )
        let encodedObject = try #require(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])

        #expect(Set(encodedObject.keys) == ["commandId", "targetHandle", "arguments"])
        #expect(encodedObject["commandId"] as? String == "setRepoSidebarSortOrder")
        #expect(encodedObject["targetHandle"] is NSNull)
        let arguments = try #require(encodedObject["arguments"] as? [String: String])
        #expect(arguments == ["order": "descending"])
    }

    @Test("command list entry argument schema encodes stable string enum shape")
    func commandListEntryArgumentSchemaEncodesStableStringEnumShape() throws {
        let entry = IPCCommandListEntry(
            id: IPCCommandIdentifier(rawValue: "setRepoSidebarSortOrder"),
            title: "Set Repo Sidebar Sort Order",
            executionModes: [.headless],
            targetKinds: [],
            requiredPrivileges: [.sidebarStateMutate],
            argumentSchema: [
                IPCCommandArgumentSchema(
                    name: "order",
                    kind: .stringEnum(values: ["ascending", "descending"]),
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
        let orderArgument = try #require(argumentSchema.first)
        #expect(orderArgument["name"] as? String == "order")
        #expect(orderArgument["isRequired"] as? Bool == true)
        let kind = try #require(orderArgument["kind"] as? [String: Any])
        #expect(kind["type"] as? String == "stringEnum")
        #expect(kind["values"] as? [String] == ["ascending", "descending"])
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

        let response = try await sendAuthenticatedAutomationRequest(
            fixture: fixture,
            request: JSONRPCClientRequest(
                id: .number(70),
                method: "command.execute",
                params: .object(["commandId": .string("futureCommand")])
            )
        )

        #expect(response.error?.code == -32_003)
        #expect(response.error?.message == "unsupported capability")
    }

    @Test("command execute forwards typed repo targets to the command port")
    func commandExecuteForwardsTypedRepoTargetsToCommandPort() async throws {
        let repoId = UUID()
        let commandPort = FakeCommandPort(
            workspaceWindowId: UUID(),
            activeScope: .commands,
            successfulCommandId: "addRepoFavorite",
            commands: [
                IPCCommandListEntry(
                    id: IPCCommandIdentifier(rawValue: "addRepoFavorite"),
                    title: "Add Favorite",
                    executionModes: [.headless],
                    targetKinds: [.repo],
                    requiredPrivileges: [.sidebarStateMutate]
                )
            ]
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
        let response = try await sendAuthenticatedAutomationRequest(
            fixture: fixture,
            request: JSONRPCClientRequest(
                id: .number(71),
                method: "command.execute",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCCommandExecuteParams(
                        commandId: IPCCommandIdentifier(rawValue: "addRepoFavorite"),
                        targetHandle: "repo:\(repoId.uuidString)"
                    )
                )
            )
        )

        #expect(response.error == nil)
        #expect(commandPort.receivedExecuteParams.count == 1)
        #expect(commandPort.receivedExecuteParams[0].targetHandle == "repo:\(repoId.uuidString)")
    }

    @Test("command execute accepts argument payload and returns command success")
    func commandExecuteAcceptsArgumentPayloadAndReturnsCommandSuccess() async throws {
        let commandPort = FakeCommandPort(
            workspaceWindowId: UUID(),
            activeScope: .commands,
            successfulCommandId: "setRepoSidebarSortOrder",
            commands: [sidebarCommandEntry("setRepoSidebarSortOrder")]
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

        let response = try await sendAuthenticatedAutomationRequest(
            fixture: fixture,
            request: JSONRPCClientRequest(
                id: .number(72),
                method: "command.execute",
                params: .object([
                    "commandId": .string("setRepoSidebarSortOrder"),
                    "arguments": .object(["order": .string("descending")]),
                ])
            )
        )

        #expect(response.error == nil)
        let result = try decodeResponseResult(IPCCommandExecuteResult.self, from: response)
        #expect(result.commandId == IPCCommandIdentifier(rawValue: "setRepoSidebarSortOrder"))
        #expect(result.applied)
        #expect(commandPort.receivedExecuteParams.map(\.arguments) == [["order": "descending"]])
    }

    @Test("debug token escrow automation can execute sidebar state commands")
    func debugTokenEscrowAutomationCanExecuteSidebarStateCommands() async throws {
        let workspaceId = UUID()
        let commandPort = FakeCommandPort(
            workspaceWindowId: UUID(),
            activeScope: .commands,
            successfulCommandId: "showWorktreeSidebar",
            commands: [
                IPCCommandListEntry(
                    id: IPCCommandIdentifier(rawValue: "showWorktreeSidebar"),
                    title: "Show Worktree Sidebar",
                    executionModes: [.headless],
                    targetKinds: [],
                    requiredPrivileges: [.sidebarStateMutate]
                )
            ],
            requiredPermissionTargetByPrivilege: [.sidebarStateMutate: .workspace(workspaceId)]
        )
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            commandPort: commandPort,
            debugTokenEscrowEnabled: true,
            debugTokenEscrowPermissionScopes: [
                IPCPermissionScope(privilege: .appCommandExecute, target: .app, dataScope: .unspecified),
                IPCPermissionScope(
                    privilege: .sidebarStateMutate, target: .workspace(workspaceId), dataScope: .sidebarState),
            ]
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try await sendDebugEscrowAutomationRequest(
            fixture: fixture,
            request: JSONRPCClientRequest(
                id: .number(75),
                method: "command.execute",
                params: .object(["commandId": .string("showWorktreeSidebar")])
            )
        )

        #expect(response.error == nil)
        let result = try decodeResponseResult(IPCCommandExecuteResult.self, from: response)
        #expect(result.applied)
        #expect(commandPort.receivedExecuteParams.map(\.commandId.rawValue) == ["showWorktreeSidebar"])
    }

    @Test("command execute requires workspace scoped sidebar mutation privilege")
    func commandExecuteRequiresWorkspaceScopedSidebarMutationPrivilege() async throws {
        let workspaceId = UUID()
        let commandPort = FakeCommandPort(
            workspaceWindowId: UUID(),
            activeScope: .commands,
            successfulCommandId: "setRepoSidebarSortOrder",
            commands: [sidebarCommandEntry("setRepoSidebarSortOrder")],
            requiredPermissionTargetByPrivilege: [.sidebarStateMutate: .workspace(workspaceId)]
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

        let appScopedResponse = try await sendAuthenticatedAutomationRequest(
            fixture: fixture,
            sidebarStateMutateTarget: .app,
            request: JSONRPCClientRequest(
                id: .number(76),
                method: "command.execute",
                params: .object([
                    "commandId": .string("setRepoSidebarSortOrder"),
                    "arguments": .object(["order": .string("descending")]),
                ])
            )
        )

        #expect(appScopedResponse.error?.code == -32_002)
        #expect(commandPort.receivedExecuteParams.isEmpty)

        let workspaceScopedResponse = try await sendAuthenticatedAutomationRequest(
            fixture: fixture,
            sidebarStateMutateTarget: .workspace(workspaceId),
            request: JSONRPCClientRequest(
                id: .number(77),
                method: "command.execute",
                params: .object([
                    "commandId": .string("setRepoSidebarSortOrder"),
                    "arguments": .object(["order": .string("descending")]),
                ])
            )
        )

        #expect(workspaceScopedResponse.error == nil)
        #expect(commandPort.receivedExecuteParams.map(\.commandId.rawValue) == ["setRepoSidebarSortOrder"])
    }

    @Test("command execute rejects wrong typed argument values as validation rejected")
    func commandExecuteRejectsWrongTypedArgumentValuesAsValidationRejected() async throws {
        let commandPort = FakeCommandPort(
            workspaceWindowId: UUID(),
            activeScope: .commands,
            successfulCommandId: "setRepoSidebarSortOrder",
            commands: [sidebarCommandEntry("setRepoSidebarSortOrder")]
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

        let response = try await sendAuthenticatedAutomationRequest(
            fixture: fixture,
            request: JSONRPCClientRequest(
                id: .number(74),
                method: "command.execute",
                params: .object([
                    "commandId": .string("setRepoSidebarSortOrder"),
                    "arguments": .object(["order": .number(1)]),
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
                stateUnavailableCommandId: "setRepoSidebarSortOrder",
                commands: [sidebarCommandEntry("setRepoSidebarSortOrder")]
            )
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try await sendAuthenticatedAutomationRequest(
            fixture: fixture,
            request: JSONRPCClientRequest(
                id: .number(73),
                method: "command.execute",
                params: .object([
                    "commandId": .string("setRepoSidebarSortOrder"),
                    "arguments": .object(["order": .string("descending")]),
                ])
            )
        )

        #expect(response.error?.code == -32_005)
        #expect(response.error?.message == "state unavailable")
    }
}

private func sidebarCommandEntry(_ commandId: String) -> IPCCommandListEntry {
    IPCCommandListEntry(
        id: IPCCommandIdentifier(rawValue: commandId),
        title: commandId,
        executionModes: [.headless],
        targetKinds: [],
        requiredPrivileges: [.sidebarStateMutate],
        argumentSchema: [
            IPCCommandArgumentSchema(
                name: "order",
                kind: .stringEnum(values: ["ascending", "descending"]),
                isRequired: true
            )
        ]
    )
}

private func sendAuthenticatedAutomationRequest(
    fixture: LiveServerFixture,
    sidebarStateMutateTarget: IPCTargetScope = .app,
    request: JSONRPCClientRequest
) async throws -> JSONRPCResponseMessage {
    let principal = IPCPrincipal(
        principalId: UUID(),
        runtimeId: fixture.runtimeId,
        accessMode: .unsafeDebug,
        kind: .automationClient,
        approvalAuthority: .noApprovalAuthority
    )
    fixture.server.grantLedger.grant(
        IPCPermissionScope(privilege: .appCommandExecute, target: .app, dataScope: .unspecified),
        to: principal.principalId
    )
    fixture.server.grantLedger.grant(
        IPCPermissionScope(privilege: .sidebarStateMutate, target: sidebarStateMutateTarget, dataScope: .sidebarState),
        to: principal.principalId
    )
    let token = try fixture.server.principalRegistry.issueSubjectToken(for: principal)
    let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
    defer {
        connection.close()
    }
    var reader = TestFrameReader()
    try await loginWithoutBlockingMainActor(connection: connection, token: token, requestId: 900, reader: &reader)
    try sendRequest(connection: connection, request: request)
    return try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
}

private func sendDebugEscrowAutomationRequest(
    fixture: LiveServerFixture,
    request: JSONRPCClientRequest
) async throws -> JSONRPCResponseMessage {
    let token = AgentStudioIPCSubjectToken(
        rawValue: try String(contentsOf: fixture.paths.debugTokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    )
    let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
    defer {
        connection.close()
    }
    var reader = TestFrameReader()
    try await loginWithoutBlockingMainActor(connection: connection, token: token, requestId: 901, reader: &reader)
    try sendRequest(connection: connection, request: request)
    return try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
}
