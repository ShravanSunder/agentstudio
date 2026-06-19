import AgentStudioIPCClientCore
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio IPC CLI client core", .serialized)
struct AgentStudioIPCClientCoreTests {
    @Test("discovers socket path from explicit flag before environment and metadata")
    func discoversSocketPathFromExplicitFlagBeforeEnvironmentAndMetadata() throws {
        let metadataURL = try writeMetadata(socketPath: "/tmp/metadata.sock")

        let socketPath = try AgentStudioIPCClientDiscovery.socketPath(
            explicitSocketPath: "/tmp/explicit.sock",
            environment: ["AGENTSTUDIO_IPC_SOCKET": "/tmp/env.sock"],
            metadataURL: metadataURL
        )

        #expect(socketPath == "/tmp/explicit.sock")
    }

    @Test("discovers socket path from metadata when flags and environment are absent")
    func discoversSocketPathFromMetadataWhenFlagsAndEnvironmentAreAbsent() throws {
        let metadataURL = try writeMetadata(socketPath: "/tmp/metadata.sock")

        let socketPath = try AgentStudioIPCClientDiscovery.socketPath(
            explicitSocketPath: nil,
            environment: [:],
            metadataURL: metadataURL
        )

        #expect(socketPath == "/tmp/metadata.sock")
    }

    @Test("parses terminal wait and event subscribe commands")
    func parsesTerminalWaitAndEventSubscribeCommands() throws {
        let statusInvocation = try AgentStudioIPCClientArguments.parse(
            ["--socket", "/tmp/app.sock", "terminal-status", "pane:1"],
            environment: [:]
        )
        let waitInvocation = try AgentStudioIPCClientArguments.parse(
            ["--socket", "/tmp/app.sock", "terminal-wait", "pane:1", "commandFinished", "5"],
            environment: [:]
        )
        let subscribeInvocation = try AgentStudioIPCClientArguments.parse(
            ["--socket", "/tmp/app.sock", "events-subscribe", "terminal.commandFinished,permission.requestCreated"],
            environment: [:]
        )

        #expect(statusInvocation.command == .terminalStatus(handle: "pane:1"))
        #expect(waitInvocation.configuration.socketPath == "/tmp/app.sock")
        #expect(
            waitInvocation.command
                == .terminalWait(handle: "pane:1", condition: .commandFinished, timeoutSeconds: 5, afterSequence: nil)
        )
        #expect(
            subscribeInvocation.command
                == .eventsSubscribe(eventNames: [.terminalCommandFinished, .permissionRequestCreated])
        )
    }

    @Test("parses pane snapshot command and builds request frame")
    func parsesPaneSnapshotCommandAndBuildsRequestFrame() throws {
        let invocation = try AgentStudioIPCClientArguments.parse(
            ["--socket", "/tmp/app.sock", "pane-snapshot", "pane:1"],
            environment: [:]
        )
        let client = AgentStudioIPCClient(configuration: invocation.configuration)

        #expect(invocation.command == .paneSnapshot(handle: "pane:1"))
        let frame = try client.requestFrame(invocation.command, requestId: 14)
        let request = try JSONRPCCodec.decodeRequest(frame)

        #expect(request.id == .number(14))
        #expect(request.method == "pane.snapshot")
        guard case .object(let params)? = request.params else {
            Issue.record("expected object params")
            return
        }
        #expect(params["handle"] == .string("pane:1"))
    }

    @Test("terminal wait can include an after sequence for replayable runtime facts")
    func terminalWaitCanIncludeAfterSequenceForReplayableRuntimeFacts() throws {
        let invocation = try AgentStudioIPCClientArguments.parse(
            ["--socket", "/tmp/app.sock", "terminal-wait", "pane:1", "commandFinished", "5", "41"],
            environment: [:]
        )
        let client = AgentStudioIPCClient(configuration: invocation.configuration)

        #expect(
            invocation.command
                == .terminalWait(handle: "pane:1", condition: .commandFinished, timeoutSeconds: 5, afterSequence: 41)
        )
        let frame = try client.requestFrame(invocation.command, requestId: 12)
        let request = try JSONRPCCodec.decodeRequest(frame)

        #expect(request.id == .number(12))
        #expect(request.method == "terminal.wait")
        guard case .object(let params)? = request.params else {
            Issue.record("expected object params")
            return
        }
        #expect(params["handle"] == .string("pane:1"))
        #expect(params["condition"] == .string("commandFinished"))
        #expect(params["timeoutSeconds"] == .number(5))
        #expect(params["afterSequence"] == .number(41))
    }

    @Test("parses auth status and command control commands")
    func parsesAuthStatusAndCommandControlCommands() throws {
        let statusInvocation = try AgentStudioIPCClientArguments.parse(
            ["--socket", "/tmp/app.sock", "auth-status"],
            environment: [:]
        )
        let listInvocation = try AgentStudioIPCClientArguments.parse(
            ["--socket", "/tmp/app.sock", "command-list"],
            environment: [:]
        )
        let executeInvocation = try AgentStudioIPCClientArguments.parse(
            ["--socket", "/tmp/app.sock", "command-execute", "showCommandBarCommands"],
            environment: [:]
        )
        let unknownExecuteInvocation = try AgentStudioIPCClientArguments.parse(
            ["--socket", "/tmp/app.sock", "command-execute", "futureCommand"],
            environment: [:]
        )

        #expect(statusInvocation.command == .authStatus)
        #expect(listInvocation.command == .commandList)
        #expect(
            executeInvocation.command
                == .commandExecute(
                    IPCCommandExecuteParams(
                        commandId: IPCCommandIdentifier(rawValue: "showCommandBarCommands"),
                        targetHandle: nil
                    )
                )
        )
        #expect(
            unknownExecuteInvocation.command
                == .commandExecute(
                    IPCCommandExecuteParams(
                        commandId: IPCCommandIdentifier(rawValue: "futureCommand"),
                        targetHandle: nil
                    )
                )
        )
    }

    @Test("parses auth token stdin mode without accepting argv bearer tokens")
    func parsesAuthTokenStdinModeWithoutAcceptingArgvBearerTokens() throws {
        let loginInvocation = try AgentStudioIPCClientArguments.parse(
            ["--socket", "/tmp/app.sock", "--token-stdin", "auth-login"],
            environment: [:]
        )

        #expect(loginInvocation.readsAuthTokenFromStandardInput)
        #expect(loginInvocation.configuration.authToken == nil)
        #expect(loginInvocation.command == .authLogin)
        #expect(throws: AgentStudioIPCClientError.self) {
            try AgentStudioIPCClientArguments.parse(
                ["--socket", "/tmp/app.sock", "--token", "secret-token", "auth-login"],
                environment: [:]
            )
        }
        #expect(throws: AgentStudioIPCClientError.self) {
            try AgentStudioIPCClientArguments.parse(
                ["--socket", "/tmp/app.sock", "auth-login", "secret-token"],
                environment: [:]
            )
        }
    }

    @Test("builds machine-readable JSON-RPC request frames")
    func buildsMachineReadableJSONRPCRequestFrames() throws {
        let client = AgentStudioIPCClient(
            configuration: AgentStudioIPCClientConfiguration(socketPath: "/tmp/app.sock")
        )

        let frame = try client.requestFrame(
            .terminalSend(
                handle: "pane:1",
                input: "echo hello\n",
                correlationId: UUID(uuidString: "00000000-0000-0000-0000-000000000201")
            ),
            requestId: 9
        )
        let request = try JSONRPCCodec.decodeRequest(frame)

        #expect(request.id == .number(9))
        #expect(request.method == "terminal.send")
        guard case .object(let params)? = request.params else {
            Issue.record("expected object params")
            return
        }
        #expect(params["handle"] == .string("pane:1"))
        #expect(params["input"] == .string("echo hello\n"))
        #expect(params["correlationId"] == .string("00000000-0000-0000-0000-000000000201"))
    }

    @Test("builds command execute request frame")
    func buildsCommandExecuteRequestFrame() throws {
        let client = AgentStudioIPCClient(
            configuration: AgentStudioIPCClientConfiguration(socketPath: "/tmp/app.sock")
        )

        let frame = try client.requestFrame(
            .commandExecute(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: "showCommandBarPanes"),
                    targetHandle: nil
                )
            ),
            requestId: 10
        )
        let request = try JSONRPCCodec.decodeRequest(frame)

        #expect(request.id == .number(10))
        #expect(request.method == "command.execute")
        guard case .object(let params)? = request.params else {
            Issue.record("expected object params")
            return
        }
        #expect(params["commandId"] == .string("showCommandBarPanes"))
        #expect(params["targetHandle"] == nil)
    }

    @Test("round trips one request against a local Unix socket test server")
    func roundTripsOneRequestAgainstLocalUnixSocketTestServer() throws {
        let endpoint = UnixSocketEndpoint(path: temporarySocketPath())
        let listener = UnixSocketListener(endpoint: endpoint)
        let handledRequest = LockedBox<JSONRPCRequest?>(nil)
        try listener.start { connection in
            var decoder = NDJSONFrameDecoder(maxFrameBytes: 65_536)
            let data = try connection.receive(maxBytes: 4096)
            let frame = try #require(try decoder.append(data).first)
            let request = try JSONRPCCodec.decodeRequest(frame)
            handledRequest.set(request)
            let response = JSONRPCResponse.success(
                id: request.id,
                result: .object(["appVersion": .string("test")])
            )
            try connection.send(
                try NDJSONFrameEncoder.encode(
                    JSONRPCCodec.encodeResponse(response),
                    maxFrameBytes: 65_536
                ))
            connection.close()
        }
        defer {
            listener.stop()
        }

        let client = AgentStudioIPCClient(
            configuration: AgentStudioIPCClientConfiguration(socketPath: endpoint.path, maxFrameBytes: 65_536)
        )
        let response = try client.call(.identify, requestId: 3)

        #expect(response.id == .number(3))
        #expect(response.result == .object(["appVersion": .string("test")]))
        #expect(handledRequest.value()?.method == "system.identify")
    }

    @Test("authenticates and calls command on the same Unix socket connection")
    func authenticatesAndCallsCommandOnSameUnixSocketConnection() throws {
        let endpoint = UnixSocketEndpoint(path: temporarySocketPath())
        let listener = UnixSocketListener(endpoint: endpoint)
        let handledMethods = LockedBox<[String]>([])
        try listener.start { connection in
            var decoder = NDJSONFrameDecoder(maxFrameBytes: 65_536)
            let loginRequest = try receiveRequest(connection: connection, decoder: &decoder)
            handledMethods.set(handledMethods.value() + [loginRequest.method])
            try connection.send(responseFrame(id: loginRequest.id, result: .object(["ok": .bool(true)])))

            let commandRequest = try receiveRequest(connection: connection, decoder: &decoder)
            handledMethods.set(handledMethods.value() + [commandRequest.method])
            try connection.send(
                responseFrame(
                    id: commandRequest.id,
                    result: .object(["appVersion": .string("authenticated")])
                ))
            connection.close()
        }
        defer {
            listener.stop()
        }

        let client = AgentStudioIPCClient(
            configuration: AgentStudioIPCClientConfiguration(
                socketPath: endpoint.path,
                authToken: "secret-token",
                maxFrameBytes: 65_536
            )
        )
        let response = try client.call(.identify, requestId: 5)

        #expect(response.id == .number(6))
        #expect(response.result == .object(["appVersion": .string("authenticated")]))
        #expect(handledMethods.value() == ["auth.login", "system.identify"])
    }

    @Test("automatic authentication error prevents follow-up command")
    func automaticAuthenticationErrorPreventsFollowupCommand() throws {
        let endpoint = UnixSocketEndpoint(path: temporarySocketPath())
        let listener = UnixSocketListener(endpoint: endpoint)
        let handledMethods = LockedBox<[String]>([])
        try listener.start { connection in
            var decoder = NDJSONFrameDecoder(maxFrameBytes: 65_536)
            let loginRequest = try receiveRequest(connection: connection, decoder: &decoder)
            handledMethods.set(handledMethods.value() + [loginRequest.method])
            try connection.send(
                errorFrame(
                    id: loginRequest.id,
                    code: -32_001,
                    message: "unauthenticated"
                ))
            connection.close()
        }
        defer {
            listener.stop()
        }

        let client = AgentStudioIPCClient(
            configuration: AgentStudioIPCClientConfiguration(
                socketPath: endpoint.path,
                authToken: "bad-token",
                maxFrameBytes: 65_536
            )
        )

        do {
            _ = try client.call(.identify, requestId: 9)
            Issue.record("client unexpectedly sent follow-up command after auth error")
        } catch let error as AgentStudioIPCClientError {
            #expect(error.reason == .authenticationFailed)
        }
        #expect(handledMethods.value() == ["auth.login"])
    }

    @Test("event subscribe keeps the socket open and surfaces notification frames")
    func eventSubscribeKeepsSocketOpenAndSurfacesNotificationFrames() throws {
        let endpoint = UnixSocketEndpoint(path: temporarySocketPath())
        let listener = UnixSocketListener(endpoint: endpoint)
        try listener.start { connection in
            var decoder = NDJSONFrameDecoder(maxFrameBytes: 65_536)
            let request = try receiveRequest(connection: connection, decoder: &decoder)
            try connection.send(
                responseFrame(
                    id: request.id,
                    result: .object([
                        "subscriptionId": .string("00000000-0000-0000-0000-000000000301")
                    ])
                )
                    + notificationFrame()
            )
            connection.close()
        }
        defer {
            listener.stop()
        }

        let client = AgentStudioIPCClient(
            configuration: AgentStudioIPCClientConfiguration(socketPath: endpoint.path, maxFrameBytes: 65_536)
        )
        var frames: [String] = []

        try client.stream(.eventsSubscribe(eventNames: [.terminalCommandFinished]), requestId: 7) { frame in
            frames.append(frame)
        }

        #expect(frames.count == 2)
        #expect(try JSONRPCCodec.decodeResponse(frames[0]).id == .number(7))
        #expect(frames[1].contains(#""method":"events.notification""#))
    }
}

private func writeMetadata(socketPath: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentstudio-ipc-client-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("runtime.json")
    let data = Data(#"{"socketPath":"\#(socketPath)","protocol":"agentstudio-ipc-jsonrpc-2"}"#.utf8)
    try data.write(to: url)
    return url
}

private func temporarySocketPath() -> String {
    let suffix = UUID().uuidString.prefix(8)
    return "/tmp/asipc-\(suffix).sock"
}

private func receiveRequest(
    connection: UnixSocketConnection,
    decoder: inout NDJSONFrameDecoder
) throws -> JSONRPCRequest {
    while true {
        let data = try connection.receive(maxBytes: 4096)
        let frames = try decoder.append(data)
        if let frame = frames.first {
            return try JSONRPCCodec.decodeRequest(frame)
        }
    }
}

private func responseFrame(id: JSONRPCIdentifier?, result: JSONValue) throws -> Data {
    try NDJSONFrameEncoder.encode(
        JSONRPCCodec.encodeResponse(JSONRPCResponse.success(id: id, result: result)),
        maxFrameBytes: 65_536
    )
}

private func errorFrame(id: JSONRPCIdentifier?, code: Int, message: String) throws -> Data {
    try NDJSONFrameEncoder.encode(
        JSONRPCCodec.encodeResponse(
            JSONRPCResponse.failure(
                id: id,
                error: JSONRPCErrorPayload(code: code, message: message)
            )),
        maxFrameBytes: 65_536
    )
}

private func notificationFrame() throws -> Data {
    try NDJSONFrameEncoder.encode(
        JSONRPCCodec.encodeNotification(
            JSONRPCNotification(
                method: "events.notification",
                params: .object(["name": .string(IPCEventName.terminalCommandFinished.rawValue)])
            )
        ),
        maxFrameBytes: 65_536
    )
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    func set(_ value: Value) {
        lock.withLock {
            storedValue = value
        }
    }

    func value() -> Value {
        lock.withLock {
            storedValue
        }
    }
}
