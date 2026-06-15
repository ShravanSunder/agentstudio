import AgentStudioIPCClientCore
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio IPC CLI client core")
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
        let waitInvocation = try AgentStudioIPCClientArguments.parse(
            ["--socket", "/tmp/app.sock", "terminal-wait", "pane:1", "commandFinished", "5"],
            environment: [:]
        )
        let subscribeInvocation = try AgentStudioIPCClientArguments.parse(
            ["--socket", "/tmp/app.sock", "events-subscribe", "terminal.commandFinished,permission.requestCreated"],
            environment: [:]
        )

        #expect(waitInvocation.configuration.socketPath == "/tmp/app.sock")
        #expect(
            waitInvocation.command
                == .terminalWait(handle: "pane:1", condition: .commandFinished, timeoutSeconds: 5)
        )
        #expect(
            subscribeInvocation.command
                == .eventsSubscribe(eventNames: [.terminalCommandFinished, .permissionRequestCreated])
        )
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
