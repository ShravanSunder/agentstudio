import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

#if canImport(Darwin)
    import Darwin
#endif

@Suite("AgentStudio App IPC service shell", .serialized)
struct AgentStudioAppIPCServiceTests {
    @Test("composes service from configuration and protocol ports")
    func composesServiceFromConfigurationAndProtocolPorts() throws {
        let method = try IPCMethodDefinition(
            name: "system.identify",
            privilegeClasses: [.systemRead],
            executionOwner: .queryReader,
            resultSemantics: .applied
        )
        let runtimeId = UUID()
        let configuration = AgentStudioAppIPCConfiguration(
            runtimeId: runtimeId,
            accessMode: .agentStudioOnly,
            methodDefinitions: [method]
        )

        let eventBroker = IPCEventBroker()
        let service = AgentStudioAppIPCService(
            configuration: configuration,
            ports: AgentStudioAppIPCPorts(
                queryPort: FakeQueryPort(),
                layoutPort: FakeLayoutPort(),
                runtimePort: FakeRuntimePort(),
                commandPort: FakeCommandPort(),
                uiPresentationPort: FakeUIPresentationPort(),
                permissionApprovalPort: FakePermissionApprovalPort()
            ),
            eventBroker: eventBroker
        )

        #expect(service.configuration.runtimeId == runtimeId)
        #expect(service.configuration.accessMode == .agentStudioOnly)
        #expect(service.configuration.methodDefinitions == [method])
        #expect(service.eventBroker === eventBroker)
    }

    @Test("server starts Unix socket and answers pre-auth ping")
    func serverStartsUnixSocketAndAnswersPreAuthPing() throws {
        let fixture = try LiveServerFixture()
        defer {
            fixture.cleanup()
        }
        try fixture.server.start(processIdentifier: 12_345, startedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(id: .number(1), method: "system.ping", params: .object([:]))
        )

        #expect(response.id == .number(1))
        guard case .object(let result)? = response.result else {
            Issue.record("expected object result")
            return
        }
        #expect(result["ok"] == .bool(true))
        #expect(result["runtimeId"] == .string(fixture.runtimeId.uuidString))

        let metadataData = try Data(contentsOf: fixture.paths.metadataURL)
        let metadata = try JSONDecoder.iso8601.decode(AgentStudioIPCRuntimeMetadata.self, from: metadataData)
        #expect(metadata.runtimeId == fixture.runtimeId)
        #expect(metadata.processIdentifier == 12_345)
        #expect(metadata.socketPath == fixture.paths.socketURL.path)
    }

    @Test("server authenticates and serves a command on the same socket")
    func serverAuthenticatesAndServesCommandOnSameSocket() throws {
        let fixture = try LiveServerFixture()
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
        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path)
        )
        defer {
            connection.close()
        }
        var frameReader = TestFrameReader()

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(10),
                method: "auth.login",
                params: .object(["token": .string(token.rawValue)])
            )
        )
        let login = try frameReader.receiveResponse(connection: connection)
        #expect(login.id == .number(10))

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(id: .number(11), method: "system.identify", params: .object([:]))
        )
        let identify = try frameReader.receiveResponse(connection: connection)

        #expect(identify.id == .number(11))
        #expect(identify.error == nil)
        guard case .object(let result)? = identify.result else {
            Issue.record("expected identify result")
            return
        }
        #expect(result["runtimeId"] == .string(fixture.runtimeId.uuidString))
        #expect(result["accessMode"] == .string(IPCAccessMode.agentStudioOnly.rawValue))
    }

    @Test("server rejects authenticated commands before login")
    func serverRejectsAuthenticatedCommandsBeforeLogin() throws {
        let fixture = try LiveServerFixture()
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(id: .number(2), method: "terminal.status", params: .object([:]))
        )

        #expect(response.id == .number(2))
        #expect(response.error?.code == -32_001)
        #expect(response.error?.message == "unauthenticated")
    }

    @Test("debug unsafe no-auth reports an explicit unsafe debug principal")
    func debugUnsafeNoAuthReportsExplicitUnsafeDebugPrincipal() throws {
        let fixture = try LiveServerFixture(accessMode: .unsafeDebug, channel: .debug)
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(id: .number(60), method: "auth.status", params: .object([:]))
        )

        #expect(response.id == .number(60))
        #expect(response.error == nil)
        guard case .object(let result)? = response.result else {
            Issue.record("expected auth status result")
            return
        }
        #expect(result["authenticated"] == .bool(true))
        #expect(result["accessMode"] == .string(IPCAccessMode.unsafeDebug.rawValue))
    }

    @Test("debug unsafe no-auth authorizes terminal send without login")
    func debugUnsafeNoAuthAuthorizesTerminalSendWithoutLogin() throws {
        let paneId = UUID()
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            panes: [makePaneSummary(id: paneId, ordinal: 1)],
            runtimePort: FakeRuntimePort(successfulPaneId: paneId)
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(61),
                method: "terminal.send",
                params: .object([
                    "handle": .string("pane:1"),
                    "input": .string("echo unsafe-debug\n"),
                ])
            )
        )

        #expect(response.id == .number(61))
        #expect(response.error == nil)
        let result = try decodeResponseResult(IPCTerminalSendInputResult.self, from: response)
        #expect(result.paneId == paneId)
        #expect(result.disposition == .accepted)
    }

    @Test("failed auth login prevents unsafe debug fallback on same socket")
    func failedAuthLoginPreventsUnsafeDebugFallbackOnSameSocket() throws {
        let paneId = UUID()
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            panes: [makePaneSummary(id: paneId, ordinal: 1)],
            runtimePort: FakeRuntimePort(successfulPaneId: paneId)
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        defer {
            connection.close()
        }
        var reader = TestFrameReader()

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(62),
                method: "auth.login",
                params: .object(["token": .string("invalid-token")])
            )
        )
        let loginResponse = try reader.receiveResponse(connection: connection)
        #expect(loginResponse.id == .number(62))
        #expect(loginResponse.error?.code == -32_001)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(63),
                method: "terminal.send",
                params: .object([
                    "handle": .string("pane:1"),
                    "input": .string("echo should-not-run\n"),
                ])
            )
        )
        let sendResponse = try reader.receiveResponse(connection: connection)
        #expect(sendResponse.id == .number(63))
        #expect(sendResponse.error?.code == -32_001)
        #expect(sendResponse.error?.message == "unauthenticated")
    }

    @Test("terminal wait forwards after sequence to runtime port")
    func terminalWaitForwardsAfterSequenceToRuntimePort() throws {
        let paneId = UUID()
        let runtimePort = RecordingWaitRuntimePort(successfulPaneId: paneId)
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            panes: [makePaneSummary(id: paneId, ordinal: 1)],
            runtimePort: runtimePort
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(64),
                method: "terminal.wait",
                params: .object([
                    "handle": .string("pane:1"),
                    "condition": .string(IPCTerminalWaitCondition.commandFinished.rawValue),
                    "timeoutSeconds": .number(1),
                    "afterSequence": .number(41),
                ])
            )
        )

        #expect(response.id == .number(64))
        #expect(response.error == nil)
        #expect(runtimePort.lastAfterSequence == 41)
        #expect(runtimePort.lastHandle == IPCHandle(kind: .pane, reference: .canonicalUUID(paneId)))
        let result = try decodeResponseResult(IPCTerminalWaitResult.self, from: response)
        #expect(result.paneId == paneId)
        #expect(result.condition == .commandFinished)
    }

    @Test("non-debug server channels ignore unsafe no-auth access mode")
    func nonDebugServerChannelsIgnoreUnsafeNoAuthAccessMode() throws {
        let fixture = try LiveServerFixture(accessMode: .unsafeDebug, channel: .beta)
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let status = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(id: .number(62), method: "auth.status", params: .object([:]))
        )
        #expect(status.error == nil)
        guard case .object(let statusResult)? = status.result else {
            Issue.record("expected auth status result")
            return
        }
        #expect(statusResult["authenticated"] == .bool(false))

        let send = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(63),
                method: "terminal.send",
                params: .object(["handle": .string("pane:1"), "input": .string("echo denied\n")])
            )
        )
        #expect(send.error?.code == -32_001)
        #expect(send.error?.message == "unauthenticated")
    }

    @Test("debug unsafe no-auth denies permission methods by default")
    func debugUnsafeNoAuthDeniesPermissionMethodsByDefault() throws {
        let fixture = try LiveServerFixture(accessMode: .unsafeDebug, channel: .debug)
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let requestParams = IPCPermissionRequestParams(
            scope: IPCPermissionScope(
                privilege: .terminalInputWrite, target: .pane(UUID().uuidString), dataScope: .terminalInput),
            reason: "unsafe debug must not request grants",
            approvalRoute: .humanPrompt
        )
        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(64),
                method: "permission.request",
                params: try JSONRPCCodec.encodeJSONValue(requestParams)
            )
        )

        #expect(response.id == .number(64))
        #expect(response.error?.code == -32_002)
        #expect(response.error?.message == "unauthorized")
    }

    @Test("debug token escrow writes owner-only token and removes it after login")
    func debugTokenEscrowWritesOwnerOnlyTokenAndRemovesItAfterLogin() throws {
        let fixture = try LiveServerFixture(
            channel: .debug,
            debugTokenEscrowEnabled: true
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start(processIdentifier: 12_346, startedAt: Date(timeIntervalSince1970: 1_800_000_001))

        #expect(FileManager.default.fileExists(atPath: fixture.paths.debugTokenURL.path))
        #expect(try fileMode(for: fixture.paths.debugTokenURL) & 0o777 == 0o600)

        let token = try String(contentsOf: fixture.paths.debugTokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!token.isEmpty)

        let metadata = try String(contentsOf: fixture.paths.metadataURL, encoding: .utf8)
        #expect(!metadata.contains(token))
        #expect(!metadata.contains(fixture.paths.debugTokenURL.path))

        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        defer {
            connection.close()
        }
        var reader = TestFrameReader()
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(65),
                method: "auth.login",
                params: .object(["token": .string(token)])
            )
        )
        let loginResponse = try reader.receiveResponse(connection: connection)
        #expect(loginResponse.error == nil)
        guard case .object(let loginResult)? = loginResponse.result else {
            Issue.record("expected auth login result")
            return
        }
        #expect(loginResult["authenticated"] == .bool(true))
        #expect(loginResult["accessMode"] == .string(IPCAccessMode.unsafeDebug.rawValue))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.debugTokenURL.path))

        let replay = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(66),
                method: "auth.login",
                params: .object(["token": .string(token)])
            )
        )
        #expect(replay.error?.code == -32_001)
        #expect(replay.error?.message == "unauthenticated")
    }

    @Test("non-debug server channels ignore debug token escrow")
    func nonDebugServerChannelsIgnoreDebugTokenEscrow() throws {
        let fixture = try LiveServerFixture(
            channel: .stable,
            debugTokenEscrowEnabled: true
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.debugTokenURL.path))
    }

    @Test("unsafe debug client can list commands and explicit UI presentation opens command bar")
    func unsafeDebugClientCanListCommandsAndExplicitUIPresentationOpensCommandBar() throws {
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

        let list = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(id: .number(67), method: "command.list", params: .object([:]))
        )
        #expect(list.error == nil)
        let listResult = try decodeResponseResult(IPCCommandListResult.self, from: list)
        #expect(listResult.commands.isEmpty)

        let execute = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(68),
                method: "command.execute",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCCommandExecuteParams(commandId: .commandPalette, targetHandle: nil)
                )
            )
        )
        #expect(execute.error?.code == -32_003)
        #expect(execute.error?.message == "requires presentation")

        let open = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(69),
                method: "ui.commandBar.open",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCCommandBarOpenParams(scope: .commands, correlationId: nil)
                )
            )
        )
        #expect(open.error == nil)
        let openResult = try decodeResponseResult(IPCCommandBarOpenResult.self, from: open)
        #expect(openResult.workspaceWindowId == windowId)
        #expect(openResult.scope == .commands)
    }

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

    @Test("spawned pane agents cannot execute command methods")
    func spawnedPaneAgentsCannotExecuteCommandMethods() throws {
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
        try login(connection: connection, token: token, requestId: 69, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(70),
                method: "command.execute",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCCommandExecuteParams(commandId: .commandPalette, targetHandle: nil)
                )
            )
        )
        let execute = try reader.receiveResponse(connection: connection)
        #expect(execute.error?.code == -32_002)
        #expect(execute.error?.message == "unauthorized")
    }

    @Test("unsafe debug client can invoke semantic layout control methods")
    func unsafeDebugClientCanInvokeSemanticLayoutControlMethods() throws {
        let paneId = UUID()
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            panes: [makePaneSummary(id: paneId, ordinal: 1)]
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let split = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(71),
                method: "pane.split",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCPaneSplitParams(handle: "pane:1", direction: .right, correlationId: nil)
                )
            )
        )
        #expect(split.error == nil)
        let splitResult = try decodeResponseResult(IPCPaneSplitResult.self, from: split)
        #expect(splitResult.targetPaneId == paneId)
        #expect(splitResult.direction == .right)

        let close = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(74),
                method: "pane.close",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCPaneCloseParams(handle: "pane:1", correlationId: nil)
                )
            )
        )
        #expect(close.error == nil)
        let closeResult = try decodeResponseResult(IPCPaneCloseResult.self, from: close)
        #expect(closeResult.paneId == paneId)

        let drawerAdd = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(75),
                method: "drawer.addPane",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCDrawerAddPaneParams(parentPaneHandle: "pane:1", correlationId: nil)
                )
            )
        )
        #expect(drawerAdd.error == nil)
        let drawerAddResult = try decodeResponseResult(IPCDrawerAddPaneResult.self, from: drawerAdd)
        #expect(drawerAddResult.parentPaneId == paneId)

        let drawerToggle = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(76),
                method: "drawer.toggle",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCDrawerToggleParams(parentPaneHandle: "pane:1", correlationId: nil)
                )
            )
        )
        #expect(drawerToggle.error == nil)
        let drawerToggleResult = try decodeResponseResult(IPCDrawerToggleResult.self, from: drawerToggle)
        #expect(drawerToggleResult.parentPaneId == paneId)
    }

    @Test("debug unsafe privilege cannot be requested through permission broker")
    func debugUnsafePrivilegeCannotBeRequestedThroughPermissionBroker() throws {
        let fixture = try LiveServerFixture()
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
        try login(connection: connection, token: token, requestId: 71, reader: &reader)

        let requestParams = IPCPermissionRequestParams(
            scope: IPCPermissionScope(privilege: .debugUnsafe, target: .app, dataScope: .unspecified),
            reason: "commands are not grantable",
            approvalRoute: .humanPrompt
        )
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(72),
                method: "permission.request",
                params: try JSONRPCCodec.encodeJSONValue(requestParams)
            )
        )
        let response = try reader.receiveResponse(connection: connection)
        #expect(response.error?.code == -32_002)
        #expect(response.error?.message == "unauthorized")
    }

    @Test("server authorizes friendly pane ordinals as concrete panes before terminal dispatch")
    func serverAuthorizesFriendlyPaneOrdinalsAsConcretePanesBeforeTerminalDispatch() throws {
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let fixture = try LiveServerFixture(panes: [
            makePaneSummary(id: firstPaneId, ordinal: 1),
            makePaneSummary(id: secondPaneId, ordinal: 2),
        ])
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let principal = IPCPrincipal(
            principalId: UUID(),
            runtimeId: fixture.runtimeId,
            accessMode: .agentStudioOnly,
            kind: .spawnedPaneAgent(boundPaneId: secondPaneId.uuidString, boundWorkspaceId: nil),
            approvalAuthority: .noApprovalAuthority
        )
        let token = try fixture.server.principalRegistry.issueSubjectToken(for: principal)
        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path)
        )
        defer {
            connection.close()
        }
        var reader = TestFrameReader()
        try login(connection: connection, token: token, requestId: 40, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(41),
                method: "terminal.send",
                params: .object([
                    "handle": .string("pane:1"),
                    "input": .string("echo should-not-dispatch\n"),
                ])
            )
        )

        let response = try reader.receiveResponse(connection: connection)
        #expect(response.id == .number(41))
        #expect(response.error?.code == -32_002)
        #expect(response.error?.message == "unauthorized")
    }

    @Test("server stop closes existing authenticated socket sessions")
    func serverStopClosesExistingAuthenticatedSocketSessions() throws {
        let fixture = try LiveServerFixture()
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
        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path)
        )
        defer {
            connection.close()
        }
        var reader = TestFrameReader()
        try login(connection: connection, token: token, requestId: 50, reader: &reader)

        fixture.server.stop()

        do {
            try sendRequest(
                connection: connection,
                request: JSONRPCClientRequest(id: .number(51), method: "system.identify", params: .object([:]))
            )
            let responseData = try connection.receive(maxBytes: 4096)
            if responseData.isEmpty {
                return
            }
            var decoder = NDJSONFrameDecoder(maxFrameBytes: 65_536)
            let frames = try decoder.append(responseData)
            let response = try JSONRPCCodec.decodeResponse(try #require(frames.first))
            #expect(response.error?.code == -32_001)
        } catch let error as UnixSocketTransportError {
            #expect(error.reason == .writeFailed || error.reason == .readFailed)
        }
    }

    @Test("pane invalidation closes existing bound principal socket sessions")
    func paneInvalidationClosesExistingBoundPrincipalSocketSessions() throws {
        let fixture = try LiveServerFixture()
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
        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path)
        )
        defer {
            connection.close()
        }
        var reader = TestFrameReader()
        try login(connection: connection, token: token, requestId: 52, reader: &reader)

        fixture.server.invalidatePrincipals(boundToPaneId: fixture.boundPaneId.uuidString)

        do {
            try sendRequest(
                connection: connection,
                request: JSONRPCClientRequest(id: .number(53), method: "system.identify", params: .object([:]))
            )
            let responseData = try connection.receive(maxBytes: 4096)
            #expect(responseData.isEmpty)
        } catch let error as UnixSocketTransportError {
            #expect(error.reason == .writeFailed || error.reason == .readFailed)
        }
    }

    @Test("server routes delegated approval authority through authenticated sockets")
    func serverRoutesDelegatedApprovalAuthorityThroughAuthenticatedSockets() throws {
        let fixture = try LiveServerFixture()
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let scenario = try makeDelegatedApprovalSocketScenario(fixture: fixture)

        let requesterConnection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path)
        )
        defer {
            requesterConnection.close()
        }
        var requesterReader = TestFrameReader()
        try login(
            connection: requesterConnection, token: scenario.requesterToken, requestId: 20, reader: &requesterReader)

        let permissionResult = try requestDelegatedPermission(
            connection: requesterConnection,
            reader: &requesterReader,
            scenario: scenario
        )

        let approverConnection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path)
        )
        defer {
            approverConnection.close()
        }
        var approverReader = TestFrameReader()
        try login(connection: approverConnection, token: scenario.approverToken, requestId: 30, reader: &approverReader)
        try resolveDelegatedPermission(
            connection: approverConnection,
            reader: &approverReader,
            permissionResult: permissionResult
        )

        try assertGrantIsActive(
            connection: requesterConnection,
            reader: &requesterReader,
            permissionResult: permissionResult
        )
    }

    @Test("pane bootstrap delivers token through inherited fd metadata only")
    func paneBootstrapDeliversTokenThroughInheritedFDMetadataOnly() throws {
        let fixture = try LiveServerFixture()
        defer {
            fixture.cleanup()
        }

        let bootstrap = try fixture.server.makePaneBootstrap(
            boundPaneId: fixture.boundPaneId.uuidString,
            boundWorkspaceId: nil
        )
        defer {
            bootstrap.closeTokenReadFileDescriptor()
        }

        let environment = bootstrap.descriptor.environment.variables
        #expect(environment["AGENTSTUDIO_IPC_SOCKET"] == fixture.paths.socketURL.path)
        #expect(environment["AGENTSTUDIO_IPC_RUNTIME_ID"] == fixture.runtimeId.uuidString)
        #expect(environment["AGENTSTUDIO_IPC_BOOTSTRAP_FD"] == String(bootstrap.descriptor.tokenReadFileDescriptor))
        #expect(!environment.keys.contains("AGENTSTUDIO_IPC_TOKEN"))
        #expect(try isCloseOnExec(fileDescriptor: bootstrap.descriptor.tokenReadFileDescriptor))

        let token = try readBootstrapToken(fileDescriptor: bootstrap.descriptor.tokenReadFileDescriptor)
        #expect(environment.values.allSatisfy { !$0.contains(token.rawValue) })
        let principal = try fixture.server.principalRegistry.authenticate(subjectToken: token)
        #expect(principal.kind == .spawnedPaneAgent(boundPaneId: fixture.boundPaneId.uuidString, boundWorkspaceId: nil))
    }
}
