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
                try connection.peerCredentials(using: DarwinPeerCredentialProvider()))
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
            var localDescriptor: Int32? = descriptors[0]
            var peerDescriptor: Int32? = descriptors[1]
            defer {
                if let localDescriptor {
                    _ = Darwin.close(localDescriptor)
                }
                if let peerDescriptor {
                    _ = Darwin.close(peerDescriptor)
                }
            }

            try UnixSocketOptions.disableSigPipe(fileDescriptor: descriptors[0])
            let connection = UnixSocketConnection(fileDescriptor: descriptors[0])
            localDescriptor = nil
            defer { connection.close() }

            if let descriptor = peerDescriptor {
                _ = Darwin.close(descriptor)
                peerDescriptor = nil
            }

            #expect(throws: UnixSocketTransportError.self) {
                try connection.send(Data("reply\n".utf8))
            }
        #endif
    }

    @Test("closed connection cannot access a reused descriptor")
    func closedConnectionCannotAccessReusedDescriptor() throws {
        #if canImport(Darwin)
            do {
                let fixture = try ReusedDescriptorSocketFixture.make()
                defer { fixture.close() }

                let credentialProvider = RecordingPeerCredentialProvider()
                #expect(throws: UnixSocketTransportError(reason: .connectionClosed)) {
                    _ = try fixture.closedConnection.peerCredentials(using: credentialProvider)
                }
                #expect(credentialProvider.invocationCount == 0)
                #expect(throws: UnixSocketTransportError(reason: .connectionClosed)) {
                    try fixture.closedConnection.send(Data("stale\n".utf8))
                }

                expectNoAvailableBytes(on: fixture.peerDescriptor)
            }

            do {
                let fixture = try ReusedDescriptorSocketFixture.make()
                defer { fixture.close() }

                _ = Data("successor\n".utf8).withUnsafeBytes { bytes in
                    Darwin.write(fixture.peerDescriptor, bytes.baseAddress, bytes.count)
                }

                #expect(throws: UnixSocketTransportError(reason: .connectionClosed)) {
                    _ = try fixture.closedConnection.receive(maxBytes: 64)
                }

                var preservedPayload = [UInt8](repeating: 0, count: 64)
                let preservedByteCount = preservedPayload.withUnsafeMutableBytes { bytes in
                    Darwin.read(fixture.reusedDescriptor, bytes.baseAddress, bytes.count)
                }
                try #require(preservedByteCount >= 0)
                let preservedText = String(bytes: preservedPayload.prefix(preservedByteCount), encoding: .utf8)
                #expect(preservedText == "successor\n")
            }
        #endif
    }
}

private struct ReusedDescriptorSocketFixture {
    let closedConnection: UnixSocketConnection
    let reusedDescriptor: Int32
    let peerDescriptor: Int32

    static func make() throws -> Self {
        var originalDescriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &originalDescriptors) == 0 else {
            throw UnixSocketTransportError(reason: .socketCreationFailed, errnoCode: errno)
        }

        let reusedDescriptor = originalDescriptors[0]
        let closedConnection = UnixSocketConnection(fileDescriptor: reusedDescriptor)
        closedConnection.close()
        _ = Darwin.close(originalDescriptors[1])

        let placeholderDescriptor = Darwin.open("/dev/null", O_RDONLY)
        guard placeholderDescriptor >= 0 else {
            throw UnixSocketTransportError(reason: .socketCreationFailed, errnoCode: errno)
        }
        if placeholderDescriptor != reusedDescriptor {
            guard Darwin.dup2(placeholderDescriptor, reusedDescriptor) == reusedDescriptor else {
                _ = Darwin.close(placeholderDescriptor)
                throw UnixSocketTransportError(reason: .socketCreationFailed, errnoCode: errno)
            }
            _ = Darwin.close(placeholderDescriptor)
        }

        var replacementDescriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &replacementDescriptors) == 0 else {
            _ = Darwin.close(reusedDescriptor)
            throw UnixSocketTransportError(reason: .socketCreationFailed, errnoCode: errno)
        }
        guard Darwin.dup2(replacementDescriptors[0], reusedDescriptor) == reusedDescriptor else {
            _ = Darwin.close(reusedDescriptor)
            _ = Darwin.close(replacementDescriptors[0])
            _ = Darwin.close(replacementDescriptors[1])
            throw UnixSocketTransportError(reason: .socketCreationFailed, errnoCode: errno)
        }
        _ = Darwin.close(replacementDescriptors[0])

        return Self(
            closedConnection: closedConnection,
            reusedDescriptor: reusedDescriptor,
            peerDescriptor: replacementDescriptors[1]
        )
    }

    func close() {
        _ = Darwin.close(reusedDescriptor)
        _ = Darwin.close(peerDescriptor)
    }
}

private func expectNoAvailableBytes(on descriptor: Int32) {
    var unexpectedByte: UInt8 = 0
    let receivedByteCount = Darwin.recv(
        descriptor,
        &unexpectedByte,
        MemoryLayout.size(ofValue: unexpectedByte),
        MSG_DONTWAIT
    )
    let receiveErrno = errno
    #expect(receivedByteCount == -1)
    #expect(receiveErrno == EAGAIN || receiveErrno == EWOULDBLOCK)
}

private final class RecordingPeerCredentialProvider: PeerCredentialProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var storedInvocationCount = 0

    var invocationCount: Int {
        lock.withLock { storedInvocationCount }
    }

    func credentials(forAcceptedSocket _: Int32) throws -> PeerCredentials {
        lock.withLock {
            storedInvocationCount += 1
        }
        return PeerCredentials(userIdentifier: getuid(), groupIdentifier: getgid())
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
        directory = URL(
            fileURLWithPath: "/tmp/asipc-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        endpoint = UnixSocketEndpoint(path: directory.appendingPathComponent("ipc.sock").path)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
