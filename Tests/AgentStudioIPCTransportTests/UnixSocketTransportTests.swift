import AgentStudioIPCTransport
import Foundation
import Testing

@Suite("Unix socket transport")
struct UnixSocketTransportTests {
    @Test("connects, sends, reads, and closes against a temp Unix socket")
    func connectsSendsReadsAndCloses() async throws {
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
        let response = try await awaitBlocking { try client.receive(maxBytes: 64) }

        #expect(String(data: response, encoding: .utf8) == "pong\n")
        #expect(await awaitSignal(accepted) == .success)
        #expect(receivedFrame.value() == "ping\n")
    }

    @Test("reads Darwin same-user peer credentials from accepted sockets")
    func readsDarwinPeerCredentials() async throws {
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

        #expect(await awaitSignal(accepted) == .success)
        #expect(credentials.value()?.userIdentifier == getuid())
    }

    /// `stop()` must retire the accept loop before it frees the listening
    /// descriptor number, otherwise the loop can call `accept` on a number the
    /// kernel has already handed to somebody else's `open`.
    ///
    /// Every claim here is read from inside the held handler, the one place
    /// where the loop is provably still alive, so no verdict depends on how
    /// fast the machine is. An earlier version asserted the ordering from the
    /// test body behind a one-second timeout and failed on a three-core runner,
    /// where the concurrent lane stretched this test from one second to two
    /// minutes without anything being wrong with `stop()`.
    @Test("stop retires the accept loop before freeing its descriptor")
    func stopRetiresAcceptLoopBeforeFreeingDescriptor() async throws {
        #if canImport(Darwin)
            let fixture = try UnixSocketFixture()
            defer { fixture.cleanup() }

            let listener = UnixSocketListener(endpoint: fixture.endpoint)
            let handlerEntered = DispatchSemaphore(value: 0)
            let releaseHandler = DispatchSemaphore(value: 0)
            let stopEntered = DispatchSemaphore(value: 0)
            let stopReturned = DispatchSemaphore(value: 0)
            let acceptedCount = LockedValue(0)
            let listeningDescriptor = LockedValue<Int32>(-1)
            let pathSeenWhileLoopAlive = LockedValue<String?>(nil)
            let stopHadReturnedWhileLoopAlive = LockedValue(true)

            try listener.start { connection in
                acceptedCount.set(acceptedCount.value() + 1)
                handlerEntered.signal()
                releaseHandler.wait()
                // This closure is the accept loop's current work item, so the
                // loop cannot have exited and `stop()` cannot have finished
                // joining it. Both readings are therefore ordering facts, not
                // timing observations. The poll is non-blocking on purpose.
                stopHadReturnedWhileLoopAlive.set(stopReturned.wait(timeout: .now()) == .success)
                pathSeenWhileLoopAlive.set(unixSocketPath(ofDescriptor: listeningDescriptor.value()))
                connection.close()
            }

            listeningDescriptor.set(
                try #require(findUnixSocketDescriptor(boundTo: fixture.endpoint.path)))

            // Arrange: occupy the loop inside the handler.
            let served = try UnixSocketClient.connect(endpoint: fixture.endpoint)
            defer { served.close() }
            #expect(await awaitSignal(handlerEntered) == .success)

            // Act
            Thread.detachNewThread {
                stopEntered.signal()
                listener.stop()
                stopReturned.signal()
            }
            #expect(await awaitSignal(stopEntered) == .success)
            releaseHandler.signal()

            // Assert: `stop()` completes once the handler returns.
            #expect(await awaitSignal(stopReturned) == .success)

            // Assert: while the loop was alive, `stop()` had not returned and
            // had not freed the descriptor. This is the ordering contract.
            #expect(stopHadReturnedWhileLoopAlive.value() == false)
            #expect(pathSeenWhileLoopAlive.value() == fixture.endpoint.path)

            // Assert: afterwards the loop is gone, the descriptor is released,
            // and a descriptor opened now is nobody else's to close.
            let probe = try TemporaryFileDescriptor()
            defer { probe.cleanup() }
            #expect(probe.isOpen)
            #expect(probe.readBack() == "listener must not own this descriptor")
            #expect(throws: (any Error).self) {
                _ = try UnixSocketClient.connect(endpoint: fixture.endpoint)
            }
            #expect(acceptedCount.value() == 1)
            #expect(unixSocketPath(ofDescriptor: listeningDescriptor.value()) != fixture.endpoint.path)
        #endif
    }

    /// A second `stop()`, and the one `deinit` runs, must not close a
    /// descriptor number that now belongs to an unrelated file.
    @Test("repeated stop leaves an unrelated descriptor untouched")
    func repeatedStopLeavesUnrelatedDescriptorUntouched() throws {
        #if canImport(Darwin)
            let fixture = try UnixSocketFixture()
            defer { fixture.cleanup() }

            let probe: TemporaryFileDescriptor
            do {
                let listener = UnixSocketListener(endpoint: fixture.endpoint)
                try listener.start { connection in connection.close() }
                listener.stop()

                // The listener's number is free now; take it before `deinit`
                // and the second `stop()` get a chance to close it again.
                probe = try TemporaryFileDescriptor()
                listener.stop()
            }

            defer { probe.cleanup() }
            #expect(probe.isOpen)
            #expect(probe.readBack() == "listener must not own this descriptor")
        #endif
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

    @Test("closed connection rejects operations before descriptor access")
    func closedConnectionRejectsOperationsBeforeDescriptorAccess() throws {
        #if canImport(Darwin)
            var descriptors: [Int32] = [0, 0]
            guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
                throw UnixSocketTransportError(reason: .socketCreationFailed, errnoCode: errno)
            }

            let connection = UnixSocketConnection(fileDescriptor: descriptors[0])
            connection.close()
            _ = Darwin.close(descriptors[1])

            let credentialProvider = RecordingPeerCredentialProvider()
            #expect(throws: UnixSocketTransportError(reason: .connectionClosed)) {
                _ = try connection.peerCredentials(using: credentialProvider)
            }
            #expect(credentialProvider.invocationCount == 0)

            #expect(throws: UnixSocketTransportError(reason: .connectionClosed)) {
                try connection.send(Data("stale\n".utf8))
            }
            #expect(throws: UnixSocketTransportError(reason: .connectionClosed)) {
                _ = try connection.receive(maxBytes: 64)
            }
        #endif
    }
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

/// A real file holding a descriptor, used to prove the listener does not close
/// a number it no longer owns. `isOpen` asks the kernel about this exact
/// descriptor rather than trusting that nothing touched it.
private struct TemporaryFileDescriptor {
    static let contents = "listener must not own this descriptor"

    let url: URL
    let descriptor: Int32

    init() throws {
        url = URL(
            fileURLWithPath: "/tmp/asipc-probe-\(UUID().uuidString.replacingOccurrences(of: "-", with: "")).txt"
        )
        try Self.contents.write(to: url, atomically: true, encoding: .utf8)
        descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw UnixSocketTransportError(reason: .socketCreationFailed, errnoCode: errno)
        }
    }

    var isOpen: Bool {
        fcntl(descriptor, F_GETFD) != -1
    }

    func readBack() -> String? {
        var buffer = [UInt8](repeating: 0, count: 256)
        let count = pread(descriptor, &buffer, buffer.count, 0)
        guard count > 0 else { return nil }
        return String(bytes: buffer[0..<count], encoding: .utf8)
    }

    func cleanup() {
        if isOpen {
            _ = close(descriptor)
        }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Reports the path a descriptor is bound to, or nil when the descriptor is
/// closed or is not a named Unix socket. `SO_ACCEPTCONN` is not available for
/// AF_UNIX on Darwin (it fails with `ENOPROTOOPT`), so the bound path is the
/// identifying fact available to a test.
private func unixSocketPath(ofDescriptor descriptor: Int32) -> String? {
    #if canImport(Darwin)
        var address = sockaddr_un()
        var addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
        let named = withUnsafeMutablePointer(to: &address) { storage in
            storage.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                getsockname(descriptor, generic, &addressLength)
            }
        }
        guard named == 0, address.sun_family == sa_family_t(AF_UNIX) else { return nil }

        let pathStorage = address.sun_path
        let boundPath = withUnsafePointer(to: pathStorage) { storage in
            storage.withMemoryRebound(
                to: CChar.self, capacity: MemoryLayout.size(ofValue: pathStorage)
            ) { characters in
                String(cString: characters)
            }
        }
        return boundPath.isEmpty ? nil : boundPath
    #else
        return nil
    #endif
}

/// Locates the listener's own descriptor. Called while the listening socket is
/// the only thing bound to `path`, so the first match is unambiguous.
private func findUnixSocketDescriptor(boundTo path: String) -> Int32? {
    #if canImport(Darwin)
        for candidate in Int32(0)..<Int32(512) where unixSocketPath(ofDescriptor: candidate) == path {
            return candidate
        }
    #endif
    return nil
}

/// Waits for a semaphore on a thread of its own and suspends the caller.
///
/// Swift Testing runs a test body on the cooperative executor, whose width is
/// the machine's core count, so a `DispatchSemaphore.wait` there removes one of
/// three threads on a CI runner for as long as it blocks. The concurrent lane
/// can crowd `DispatchQueue.global()` as well, so this takes a thread of its
/// own, which is always schedulable. The deadline is a liveness backstop rather
/// than a verdict about speed: every caller asserts success, and a machine
/// being slow cannot turn a passing run into a failing one.
private func awaitSignal(
    _ semaphore: DispatchSemaphore,
    deadline: DispatchTimeInterval = .seconds(120)
) async -> DispatchTimeoutResult {
    await withCheckedContinuation { continuation in
        Thread.detachNewThread {
            continuation.resume(returning: semaphore.wait(timeout: .now() + deadline))
        }
    }
}

/// The same hop for a blocking socket call, which parks a cooperative thread
/// for as long as the peer takes to answer.
private func awaitBlocking<Value: Sendable>(
    _ blockingWork: @escaping @Sendable () throws -> Value
) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
        Thread.detachNewThread {
            do {
                continuation.resume(returning: try blockingWork())
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
