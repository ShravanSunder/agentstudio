import AgentStudioIPCTransport
import Foundation
import Testing

@Suite("Unix socket transport")
struct UnixSocketTransportTests {
    @Test("connects, sends, reads, and closes against a temp Unix socket")
    func connectsSendsReadsAndCloses() throws {
        let fixture = try UnixSocketFixture()
        defer { fixture.cleanup() }

        let listener = UnixSocketListener(endpoint: fixture.endpoint)
        let receivedFrame = LockedValue<String?>(nil)
        let accepted = DispatchSemaphore(value: 0)

        try listener.start { connection in
            defer {
                connection.close()
                accepted.signal()
            }

            let request = try connection.receive(maxBytes: 64)
            receivedFrame.set(String(data: request, encoding: .utf8))
            try connection.send(Data("pong\n".utf8))
        }
        defer { listener.stop() }

        let client = try UnixSocketClient.connect(endpoint: fixture.endpoint)
        defer { client.close() }

        try client.send(Data("ping\n".utf8))
        let response = try client.receive(maxBytes: 64)

        #expect(String(data: response, encoding: .utf8) == "pong\n")
        #expect(accepted.wait(timeout: .now() + 2) == .success)
        #expect(receivedFrame.value() == "ping\n")
    }

    @Test("reads Darwin same-user peer credentials from accepted sockets")
    func readsDarwinPeerCredentials() throws {
        let fixture = try UnixSocketFixture()
        defer { fixture.cleanup() }

        let listener = UnixSocketListener(endpoint: fixture.endpoint)
        let credentials = LockedValue<PeerCredentials?>(nil)
        let accepted = DispatchSemaphore(value: 0)

        try listener.start { connection in
            defer {
                connection.close()
                accepted.signal()
            }

            credentials.set(
                try DarwinPeerCredentialProvider().credentials(forAcceptedSocket: connection.fileDescriptor))
        }
        defer { listener.stop() }

        let client = try UnixSocketClient.connect(endpoint: fixture.endpoint)
        defer { client.close() }

        #expect(accepted.wait(timeout: .now() + 2) == .success)
        #expect(credentials.value()?.userIdentifier == getuid())
    }

    @Test("send to a disconnected peer fails without SIGPIPE")
    func sendToDisconnectedPeerFailsWithoutSIGPIPE() throws {
        #if canImport(Darwin)
            var descriptors: [Int32] = [0, 0]
            guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
                throw UnixSocketTransportError(reason: .socketCreationFailed, errnoCode: errno)
            }
            defer {
                _ = Darwin.close(descriptors[0])
                _ = Darwin.close(descriptors[1])
            }

            try UnixSocketOptions.disableSigPipe(fileDescriptor: descriptors[0])
            let connection = UnixSocketConnection(fileDescriptor: descriptors[0])
            defer { connection.close() }

            _ = Darwin.close(descriptors[1])

            #expect(throws: UnixSocketTransportError.self) {
                try connection.send(Data("reply\n".utf8))
            }
        #endif
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    func set(_ value: Value) {
        lock.withLock {
            storage = value
        }
    }

    func value() -> Value {
        lock.withLock {
            storage
        }
    }
}

private struct UnixSocketFixture {
    let directory: URL
    let endpoint: UnixSocketEndpoint

    init() throws {
        directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("asipc-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        endpoint = UnixSocketEndpoint(path: directory.appendingPathComponent("ipc.sock").path)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
