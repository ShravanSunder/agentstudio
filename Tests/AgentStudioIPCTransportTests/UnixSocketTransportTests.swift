import Foundation
import Testing

@testable import AgentStudioIPCTransport

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

    /// The normal wake-and-join branch must retain the listening descriptor
    /// until the real accept-queue barrier runs. The controlled wait blocks on
    /// that actual barrier, so success is never fabricated by the test.
    @Test("normal stop joins the accept loop before freeing its descriptor")
    func normalStopJoinsAcceptLoopBeforeFreeingDescriptor() async throws {
        #if canImport(Darwin)
            let fixture = try UnixSocketFixture()
            defer { fixture.cleanup() }

            let handlerEntered = DispatchSemaphore(value: 0)
            let releaseHandler = DispatchSemaphore(value: 0)
            let stopDidReturn = LockedValue(false)
            let stopReturned = DispatchSemaphore(value: 0)
            let acceptedCount = LockedValue(0)
            let listeningDescriptor = LockedValue<Int32>(-1)
            let joinWait = UnixSocketShutdownWaitController(
                mode: .waitForFirstBarrier,
                firstEntryOwnsEndpoint: {
                    unixSocketPath(ofDescriptor: listeningDescriptor.value())
                        == fixture.endpoint.path
                }
            )
            let listener = UnixSocketListener(
                endpoint: fixture.endpoint,
                acceptLoopJoinWait: { barrier in joinWait.wait(for: barrier) }
            )

            try listener.start { connection in
                acceptedCount.set(acceptedCount.value() + 1)
                handlerEntered.signal()
                releaseHandler.wait()
                connection.close()
            }
            defer { listener.stop() }

            do {
                listeningDescriptor.set(
                    try #require(findUnixSocketDescriptor(boundTo: fixture.endpoint.path)))

                // Arrange: occupy the loop inside the handler.
                let served = try UnixSocketClient.connect(endpoint: fixture.endpoint)
                defer { served.close() }
                #expect(await awaitSignal(handlerEntered) == .success)

                // Act
                Thread.detachNewThread {
                    listener.stop()
                    stopDidReturn.set(true)
                    stopReturned.signal()
                }
                let joinEntry = await joinWait.waitUntilFirstEntry()
                let stopReturnedBeforeRelease = stopDidReturn.value()
                let pathWhileJoinWaits = unixSocketPath(ofDescriptor: listeningDescriptor.value())
                releaseHandler.signal()
                let stopCompletion = await awaitSignal(stopReturned)

                // Assert: afterwards the loop is gone, the descriptor is released,
                // and a descriptor opened now is nobody else's to close.
                #expect(joinEntry == .success)
                #expect(joinWait.firstEntryOwnedEndpoint == true)
                #expect(!stopReturnedBeforeRelease)
                #expect(pathWhileJoinWaits == fixture.endpoint.path)
                #expect(stopCompletion == .success)
                let probe = try TemporaryFileDescriptor()
                defer { probe.cleanup() }
                #expect(probe.isOpen)
                #expect(probe.readBack() == "listener must not own this descriptor")
                #expect(throws: (any Error).self) {
                    _ = try UnixSocketClient.connect(endpoint: fixture.endpoint)
                }
                #expect(acceptedCount.value() == 1)
                #expect(
                    unixSocketPath(ofDescriptor: listeningDescriptor.value()) != fixture.endpoint.path)
            } catch {
                let fixtureError = error
                releaseHandler.signal()
                do {
                    try await awaitBlocking { listener.stop() }
                } catch {
                    Issue.record("listener cleanup unexpectedly failed: \(error)")
                }
                throw fixtureError
            }
        #endif
    }

    /// When the first bounded join expires, production closes the descriptor
    /// before its second join. That fallback cannot promise normal-path
    /// retention, only that the old descriptor no longer owns this endpoint.
    @Test("fallback closes before its second accept-loop join")
    func fallbackClosesBeforeSecondAcceptLoopJoin() async throws {
        #if canImport(Darwin)
            let fixture = try UnixSocketFixture()
            defer { fixture.cleanup() }

            let handlerEntered = DispatchSemaphore(value: 0)
            let releaseHandler = DispatchSemaphore(value: 0)
            let stopDidReturn = LockedValue(false)
            let stopReturned = DispatchSemaphore(value: 0)
            let listeningDescriptor = LockedValue<Int32>(-1)
            let joinWait = UnixSocketShutdownWaitController(
                mode: .timeOutFirstAndWaitForSecondBarrier,
                firstEntryOwnsEndpoint: {
                    unixSocketPath(ofDescriptor: listeningDescriptor.value())
                        == fixture.endpoint.path
                }
            )
            let listener = UnixSocketListener(
                endpoint: fixture.endpoint,
                acceptLoopJoinWait: { barrier in joinWait.wait(for: barrier) }
            )

            try listener.start { connection in
                handlerEntered.signal()
                releaseHandler.wait()
                connection.close()
            }
            defer { listener.stop() }

            do {
                listeningDescriptor.set(
                    try #require(findUnixSocketDescriptor(boundTo: fixture.endpoint.path)))
                let served = try UnixSocketClient.connect(endpoint: fixture.endpoint)
                defer { served.close() }
                #expect(await awaitSignal(handlerEntered) == .success)

                // Act
                Thread.detachNewThread {
                    listener.stop()
                    stopDidReturn.set(true)
                    stopReturned.signal()
                }
                let firstJoinEntry = await joinWait.waitUntilFirstEntry()
                let secondJoinEntry = await joinWait.waitUntilSecondEntry()
                let pathAtSecondJoin = unixSocketPath(ofDescriptor: listeningDescriptor.value())
                let stopReturnedAtSecondJoin = stopDidReturn.value()
                releaseHandler.signal()
                let stopCompletion = await awaitSignal(stopReturned)
                let firstBarrierDrain = await joinWait.drainBarrier(at: 0)

                // Assert
                #expect(firstJoinEntry == .success)
                #expect(secondJoinEntry == .success)
                #expect(joinWait.firstEntryOwnedEndpoint == true)
                #expect(pathAtSecondJoin != fixture.endpoint.path)
                #expect(!stopReturnedAtSecondJoin)
                #expect(stopCompletion == .success)
                #expect(firstBarrierDrain == .success)
                #expect(joinWait.invocationCount == 2)
                #expect(throws: (any Error).self) {
                    _ = try UnixSocketClient.connect(endpoint: fixture.endpoint)
                }
            } catch {
                let fixtureError = error
                releaseHandler.signal()
                do {
                    try await awaitBlocking { listener.stop() }
                } catch {
                    Issue.record("listener cleanup unexpectedly failed: \(error)")
                }
                throw fixtureError
            }
        #endif
    }

    /// A handler that outlives both existing join budgets cannot strand the
    /// stop caller. This selects both deadline-exceeded results without using
    /// elapsed time as the verdict, then drains both real queue barriers.
    @Test("stop returns after both bounded accept-loop joins expire")
    func stopReturnsAfterBothBoundedAcceptLoopJoinsExpire() async throws {
        #if canImport(Darwin)
            let fixture = try UnixSocketFixture()
            defer { fixture.cleanup() }

            let handlerEntered = DispatchSemaphore(value: 0)
            let releaseHandler = DispatchSemaphore(value: 0)
            let stopReturned = DispatchSemaphore(value: 0)
            let listeningDescriptor = LockedValue<Int32>(-1)
            let joinWait = UnixSocketShutdownWaitController(
                mode: .timeOutBothBarriers,
                firstEntryOwnsEndpoint: {
                    unixSocketPath(ofDescriptor: listeningDescriptor.value())
                        == fixture.endpoint.path
                }
            )
            let listener = UnixSocketListener(
                endpoint: fixture.endpoint,
                acceptLoopJoinWait: { barrier in joinWait.wait(for: barrier) }
            )

            try listener.start { connection in
                handlerEntered.signal()
                releaseHandler.wait()
                connection.close()
            }
            defer { listener.stop() }

            do {
                listeningDescriptor.set(
                    try #require(findUnixSocketDescriptor(boundTo: fixture.endpoint.path)))
                let served = try UnixSocketClient.connect(endpoint: fixture.endpoint)
                defer { served.close() }
                #expect(await awaitSignal(handlerEntered) == .success)

                // Act
                Thread.detachNewThread {
                    listener.stop()
                    stopReturned.signal()
                }
                let firstJoinEntry = await joinWait.waitUntilFirstEntry()
                let secondJoinEntry = await joinWait.waitUntilSecondEntry()
                let pathAtSecondJoin = unixSocketPath(ofDescriptor: listeningDescriptor.value())
                let stopCompletionWhileHandlerHeld = await awaitSignal(stopReturned)
                releaseHandler.signal()
                let firstBarrierDrain = await joinWait.drainBarrier(at: 0)
                let secondBarrierDrain = await joinWait.drainBarrier(at: 1)
                let selectedJoinCount = joinWait.invocationCount
                listener.stop()
                let joinCountAfterRepeatedStop = joinWait.invocationCount

                // Assert
                #expect(firstJoinEntry == .success)
                #expect(secondJoinEntry == .success)
                #expect(joinWait.firstEntryOwnedEndpoint == true)
                #expect(pathAtSecondJoin != fixture.endpoint.path)
                #expect(stopCompletionWhileHandlerHeld == .success)
                #expect(firstBarrierDrain == .success)
                #expect(secondBarrierDrain == .success)
                #expect(selectedJoinCount == 2)
                #expect(joinCountAfterRepeatedStop == 3)
                #expect(throws: (any Error).self) {
                    _ = try UnixSocketClient.connect(endpoint: fixture.endpoint)
                }
            } catch {
                let fixtureError = error
                releaseHandler.signal()
                do {
                    try await awaitBlocking { listener.stop() }
                } catch {
                    Issue.record("listener cleanup unexpectedly failed: \(error)")
                }
                throw fixtureError
            }
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
