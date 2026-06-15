import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

#if canImport(Darwin)
    import Darwin
#endif

@Suite("AgentStudio App IPC service shell")
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

private struct LiveServerFixture {
    let runtimeId = UUID()
    let boundPaneId = UUID()
    let rootURL: URL
    let paths: AgentStudioIPCPaths
    let server: AgentStudioAppIPCServer

    init(panes: [IPCPaneSummary] = []) throws {
        rootURL = URL(fileURLWithPath: "/tmp/asipc-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        #if canImport(Darwin)
            _ = chmod(rootURL.path, 0o700)
        #endif
        paths = AgentStudioIPCPathResolver().paths(rootDirectory: rootURL)
        let methodRegistry = try AppIPCMethodRegistry.phaseOne()
        let service = AgentStudioAppIPCService(
            configuration: AgentStudioAppIPCConfiguration(
                runtimeId: runtimeId,
                accessMode: .agentStudioOnly,
                methodDefinitions: methodRegistry.definitions
            ),
            ports: AgentStudioAppIPCPorts(
                queryPort: FakeQueryPort(runtimeId: runtimeId, panes: panes),
                layoutPort: FakeLayoutPort(),
                runtimePort: FakeRuntimePort(),
                permissionApprovalPort: FakePermissionApprovalPort()
            )
        )
        server = AgentStudioAppIPCServer(service: service, paths: paths, channel: .debug)
    }

    func cleanup() {
        server.stop()
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func makePaneSummary(id: UUID, ordinal: Int) -> IPCPaneSummary {
    IPCPaneSummary(
        id: id,
        ordinal: ordinal,
        contentKind: .terminal,
        residency: .active,
        tabId: nil,
        repoId: nil,
        worktreeId: nil,
        isActive: false,
        isDrawerChild: false
    )
}

private struct DelegatedApprovalSocketScenario {
    let requestedScope: IPCPermissionScope
    let approverPrincipalId: UUID
    let requesterToken: AgentStudioIPCSubjectToken
    let approverToken: AgentStudioIPCSubjectToken
}

private func makeDelegatedApprovalSocketScenario(fixture: LiveServerFixture) throws -> DelegatedApprovalSocketScenario {
    let requestedScope = IPCPermissionScope(
        privilege: .terminalInputWrite,
        target: .pane(UUID().uuidString),
        dataScope: .terminalInput
    )
    let requester = IPCPrincipal(
        principalId: UUID(),
        runtimeId: fixture.runtimeId,
        accessMode: .agentStudioOnly,
        kind: .spawnedPaneAgent(boundPaneId: fixture.boundPaneId.uuidString, boundWorkspaceId: nil),
        approvalAuthority: .noApprovalAuthority
    )
    let approver = IPCPrincipal(
        principalId: UUID(),
        runtimeId: fixture.runtimeId,
        accessMode: .agentStudioOnly,
        kind: .spawnedPaneAgent(boundPaneId: UUID().uuidString, boundWorkspaceId: nil),
        approvalAuthority: .delegatedApprover(
            scopes: [
                IPCApprovalScope(
                    privilege: requestedScope.privilege,
                    target: requestedScope.target,
                    dataScope: requestedScope.dataScope
                )
            ]
        )
    )

    return try DelegatedApprovalSocketScenario(
        requestedScope: requestedScope,
        approverPrincipalId: approver.principalId,
        requesterToken: fixture.server.principalRegistry.issueSubjectToken(for: requester),
        approverToken: fixture.server.principalRegistry.issueSubjectToken(for: approver)
    )
}

private func requestDelegatedPermission(
    connection: UnixSocketConnection,
    reader: inout TestFrameReader,
    scenario: DelegatedApprovalSocketScenario
) throws -> IPCPermissionRequestResult {
    let requestParams = IPCPermissionRequestParams(
        scope: scenario.requestedScope,
        reason: "paired pane",
        approvalRoute: .delegatedPrincipal(scenario.approverPrincipalId)
    )
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(
            id: .number(21),
            method: "permission.request",
            params: try JSONRPCCodec.encodeJSONValue(requestParams)
        )
    )
    let permissionRequest = try reader.receiveResponse(connection: connection)
    #expect(permissionRequest.error == nil)
    let permissionResult = try decodeResponseResult(
        IPCPermissionRequestResult.self,
        from: permissionRequest
    )
    #expect(permissionResult.state == .pending)
    return permissionResult
}

private func resolveDelegatedPermission(
    connection: UnixSocketConnection,
    reader: inout TestFrameReader,
    permissionResult: IPCPermissionRequestResult
) throws {
    try assertPendingApprovalVisible(
        connection: connection,
        reader: &reader,
        permissionResult: permissionResult
    )
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(
            id: .number(32),
            method: "permission.resolveRequest",
            params: .object([
                "requestId": .string(permissionResult.requestId.uuidString),
                "decision": .string(ApprovalPolicyDecision.approve.rawValue),
            ])
        )
    )
    let resolvedApproval = try reader.receiveResponse(connection: connection)
    #expect(resolvedApproval.error == nil)
    let resolvedResult = try decodeResponseResult(
        IPCPermissionRequestResult.self,
        from: resolvedApproval
    )
    #expect(resolvedResult.state == .granted)
}

private func assertPendingApprovalVisible(
    connection: UnixSocketConnection,
    reader: inout TestFrameReader,
    permissionResult: IPCPermissionRequestResult
) throws {
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(id: .number(31), method: "permission.pendingApprovals", params: .object([:]))
    )
    let pendingApprovals = try reader.receiveResponse(connection: connection)
    #expect(pendingApprovals.error == nil)
    guard
        case .object(let pendingResult)? = pendingApprovals.result,
        case .array(let requests)? = pendingResult["requests"]
    else {
        Issue.record("expected pending approval requests array")
        return
    }
    #expect(requests.count == 1)
    let pendingResultValue = try decodeJSONValue(IPCPermissionRequestResult.self, from: requests[0])
    #expect(pendingResultValue.requestId == permissionResult.requestId)
}

private func assertGrantIsActive(
    connection: UnixSocketConnection,
    reader: inout TestFrameReader,
    permissionResult: IPCPermissionRequestResult
) throws {
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(
            id: .number(22),
            method: "permission.grantStatus",
            params: .object(["requestId": .string(permissionResult.requestId.uuidString)])
        )
    )
    let grantStatus = try reader.receiveResponse(connection: connection)
    let grantStatusResult = try decodeResponseResult(IPCPermissionGrantStatusResult.self, from: grantStatus)
    #expect(grantStatusResult.state == .granted)
    #expect(grantStatusResult.active)
}

private func sendRequest(socketPath: String, request: JSONRPCClientRequest) throws -> JSONRPCResponseMessage {
    let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: socketPath))
    defer {
        connection.close()
    }
    try sendRequest(connection: connection, request: request)
    var reader = TestFrameReader()
    return try reader.receiveResponse(connection: connection)
}

private func sendRequest(connection: UnixSocketConnection, request: JSONRPCClientRequest) throws {
    try connection.send(
        try NDJSONFrameEncoder.encode(
            JSONRPCCodec.encodeRequest(request),
            maxFrameBytes: 65_536
        ))
}

private func login(
    connection: UnixSocketConnection,
    token: AgentStudioIPCSubjectToken,
    requestId: Int,
    reader: inout TestFrameReader
) throws {
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(
            id: .number(requestId),
            method: "auth.login",
            params: .object(["token": .string(token.rawValue)])
        )
    )
    let response = try reader.receiveResponse(connection: connection)
    #expect(response.id == .number(requestId))
    #expect(response.error == nil)
}

private func decodeResponseResult<T: Decodable>(
    _ type: T.Type,
    from response: JSONRPCResponseMessage
) throws -> T {
    let result = try #require(response.result)
    return try decodeJSONValue(type, from: result)
}

private func decodeJSONValue<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(type, from: data)
}

private struct TestFrameReader {
    var decoder = NDJSONFrameDecoder(maxFrameBytes: 65_536)
    var queuedFrames: [String] = []

    mutating func receiveResponse(connection: UnixSocketConnection) throws -> JSONRPCResponseMessage {
        if !queuedFrames.isEmpty {
            return try JSONRPCCodec.decodeResponse(queuedFrames.removeFirst())
        }
        while true {
            let data = try connection.receive(maxBytes: 4096)
            queuedFrames.append(contentsOf: try decoder.append(data))
            if !queuedFrames.isEmpty {
                return try JSONRPCCodec.decodeResponse(queuedFrames.removeFirst())
            }
        }
    }
}

private func readBootstrapToken(fileDescriptor: Int32) throws -> AgentStudioIPCSubjectToken {
    #if canImport(Darwin)
        var buffer = [UInt8](repeating: 0, count: 128)
        let bytesRead = Darwin.read(fileDescriptor, &buffer, buffer.count)
        guard bytesRead > 0 else {
            throw AgentStudioIPCPaneBootstrapError(reason: .tokenWriteFailed, errnoCode: errno)
        }
        guard
            let rawValue = String(bytes: buffer.prefix(bytesRead), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            throw AgentStudioIPCPaneBootstrapError(reason: .tokenWriteFailed, errnoCode: errno)
        }
        return AgentStudioIPCSubjectToken(rawValue: rawValue)
    #else
        throw AgentStudioIPCPaneBootstrapError(reason: .unsupportedPlatform)
    #endif
}

private func isCloseOnExec(fileDescriptor: Int32) throws -> Bool {
    #if canImport(Darwin)
        let flags = fcntl(fileDescriptor, F_GETFD)
        guard flags >= 0 else {
            throw AgentStudioIPCPaneBootstrapError(reason: .pipeConfigurationFailed, errnoCode: errno)
        }
        return flags & FD_CLOEXEC == FD_CLOEXEC
    #else
        throw AgentStudioIPCPaneBootstrapError(reason: .unsupportedPlatform)
    #endif
}

private struct FakeQueryPort: AppIPCQueryPort {
    let runtimeId: UUID
    let panes: [IPCPaneSummary]

    nonisolated init(runtimeId: UUID = UUID(), panes: [IPCPaneSummary] = []) {
        self.runtimeId = runtimeId
        self.panes = panes
    }

    func systemIdentify() throws -> IPCSystemIdentifyResult {
        IPCSystemIdentifyResult(runtimeId: runtimeId, accessMode: .agentStudioOnly, appVersion: "test")
    }

    func systemVersion() throws -> IPCSystemVersionResult {
        IPCSystemVersionResult(appVersion: "test")
    }

    func systemCapabilities() throws -> IPCSystemCapabilitiesResult {
        IPCSystemCapabilitiesResult(methods: [])
    }

    func listWindows() throws -> IPCWindowListResult {
        IPCWindowListResult(windows: [])
    }

    func currentWindow() throws -> IPCCurrentWindowResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func listWorkspaces() throws -> IPCWorkspaceListResult {
        IPCWorkspaceListResult(workspaces: [])
    }

    func currentWorkspace() throws -> IPCCurrentWorkspaceResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func listPanes() throws -> IPCPaneListResult {
        IPCPaneListResult(panes: panes)
    }

    func currentPane() throws -> IPCPaneSnapshotResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func snapshotPane(_: UUID) throws -> IPCPaneSnapshotResult {
        throw AppIPCQueryError(reason: .targetNotFound)
    }
}

private struct FakeLayoutPort: AppIPCLayoutPort {
    func focusPane(_: IPCHandle) throws -> IPCPaneFocusResult {
        throw AppIPCLayoutError(reason: .targetNotFound)
    }
}

private struct FakeRuntimePort: AppIPCRuntimePort {
    func terminalStatus(_ handle: IPCHandle) throws -> IPCTerminalStatusResult {
        throw AppIPCRuntimeError(reason: .noRuntime)
    }

    func terminalSnapshot(_ handle: IPCHandle) throws -> IPCTerminalSnapshotResult {
        throw AppIPCRuntimeError(reason: .noRuntime)
    }

    func sendTerminalInput(
        to handle: IPCHandle,
        input: String,
        correlationId: UUID?
    ) async throws -> IPCTerminalSendInputResult {
        throw AppIPCRuntimeError(reason: .noRuntime)
    }

    func waitForTerminal(
        _ handle: IPCHandle,
        condition: IPCTerminalWaitCondition,
        timeout: Duration
    ) async throws -> IPCTerminalWaitResult {
        throw AppIPCRuntimeError(reason: .timeout)
    }
}

private struct FakePermissionApprovalPort: AppIPCPermissionApprovalPort {
    func decision(for _: PermissionRecord, requester _: IPCPrincipal) -> ApprovalPolicyDecision {
        .ask
    }
}

extension JSONDecoder {
    fileprivate static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
