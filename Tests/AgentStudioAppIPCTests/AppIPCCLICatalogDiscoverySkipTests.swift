import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

/// The provider hooks and the model verbs run several times a turn under short
/// timeouts, so what matters is not only that they answer but that they do not
/// pull the whole self-describing catalog first. A proxy in front of the real
/// server records exactly which methods the built CLI asks for.
@Suite("App IPC CLI catalog discovery skip", .serialized)
struct AppIPCCLICatalogDiscoverySkipTests {
    @Test("a session verb reaches the server without fetching the catalog")
    func sessionVerbSkipsCatalogDiscovery() throws {
        let observed = try runCLIThroughRecordingProxy(arguments: ["message", "hi"])

        #expect(!observed.contains("system.capabilities"))
        #expect(observed.contains("session.message"))
    }

    @Test("a session method named outright also skips the catalog")
    func namedSessionMethodSkipsCatalogDiscovery() throws {
        let observed = try runCLIThroughRecordingProxy(
            arguments: ["session.query", "--handle", "self"])

        #expect(!observed.contains("system.capabilities"))
        #expect(observed.contains("session.query"))
    }

    @Test("a bare --json on a parameterless method means no parameters")
    func bareJSONFlagMeansNoParameters() throws {
        let fixture = try LiveServerFixture(accessMode: .unsafeDebug, channel: .debug)
        defer { fixture.cleanup() }
        try fixture.server.start()
        var environment = ProcessInfo.processInfo.environment
        environment["AGENTSTUDIO_IPC_SOCKET"] = fixture.paths.socketURL.path
        environment.removeValue(forKey: "AGENTSTUDIO_PANE_TOKEN")

        let bare = try runCLI(
            executableURL: try cliExecutableURL(), arguments: ["system.ping", "--json"],
            environment: environment)
        let plain = try runCLI(
            executableURL: try cliExecutableURL(), arguments: ["system.ping"],
            environment: environment)

        #expect(bare.exitCode == 0, "stderr: \(String(data: bare.standardError, encoding: .utf8) ?? "")")
        #expect(bare.standardOutput == plain.standardOutput)
    }

    @Test("command.execute still resolves its arguments from the live catalog")
    func commandExecuteStillDiscovers() throws {
        let observed = try runCLIThroughRecordingProxy(
            arguments: ["command.execute", "--json", #"{"commandId":"x","correlationId":"y"}"#])

        #expect(observed.contains("system.capabilities"))
    }
}

/// Runs the built CLI against a proxy that forwards to the real server and
/// records every request method the client sends.
private func runCLIThroughRecordingProxy(arguments: [String]) throws -> [String] {
    let fixture = try LiveServerFixture(accessMode: .unsafeDebug, channel: .debug)
    defer { fixture.cleanup() }
    try fixture.server.start()
    let recorder = RequestMethodRecorder()
    let proxyPath = "/tmp/asipc-skip-\(UUIDv7.generate().uuidString).sock"
    let proxy = UnixSocketListener(endpoint: UnixSocketEndpoint(path: proxyPath))
    try proxy.start { clientConnection in
        guard
            let serverConnection = try? UnixSocketClient.connect(
                endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        else {
            clientConnection.close()
            return
        }
        pumpRecordingRequests(from: clientConnection, to: serverConnection, recorder: recorder)
        pumpResponses(from: serverConnection, to: clientConnection)
    }
    defer {
        proxy.stop()
        try? FileManager.default.removeItem(atPath: proxyPath)
    }

    var environment = ProcessInfo.processInfo.environment
    environment["AGENTSTUDIO_IPC_SOCKET"] = proxyPath
    environment.removeValue(forKey: "AGENTSTUDIO_PANE_TOKEN")
    _ = try runCLI(
        executableURL: try cliExecutableURL(), arguments: arguments, environment: environment)
    return recorder.methods()
}

private func pumpRecordingRequests(
    from source: UnixSocketConnection,
    to destination: UnixSocketConnection,
    recorder: RequestMethodRecorder
) {
    DispatchQueue.global(qos: .userInitiated).async {
        var decoder = NDJSONFrameDecoder(maxFrameBytes: IPCFramePolicy.maximumRequestFrameBytes)
        while true {
            guard let data = try? source.receive(maxBytes: 16_384), !data.isEmpty else { break }
            if let frames = try? decoder.append(data) {
                for frame in frames {
                    if let request = try? JSONRPCCodec.decodeRequest(frame) {
                        recorder.record(request.method)
                    }
                }
            }
            guard (try? destination.send(data)) != nil else { break }
        }
        destination.close()
    }
}

private func pumpResponses(from source: UnixSocketConnection, to destination: UnixSocketConnection) {
    DispatchQueue.global(qos: .userInitiated).async {
        while true {
            guard let data = try? source.receive(maxBytes: 16_384), !data.isEmpty else { break }
            guard (try? destination.send(data)) != nil else { break }
        }
        destination.close()
    }
}

private final class RequestMethodRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    func record(_ method: String) {
        lock.withLock { recorded.append(method) }
    }

    func methods() -> [String] {
        lock.withLock { recorded }
    }
}
