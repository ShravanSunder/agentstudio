import AgentStudioIPCTransport
import AgentStudioPrimitives
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudioIPCClientCore

#if canImport(Darwin)
    import Darwin
#endif

@Suite("Offline pane notification spool writer")
struct PaneNotificationSpoolWriterTests {
    @Test("an eligible message appends exactly the wire request line to an owner-only file")
    func eligibleMessageAppendsTheWireRequestLine() throws {
        // Arrange
        let fixture = try PaneNotificationSpoolFixture()
        defer { fixture.remove() }
        let invocation = try fixture.invocation(["message", "deploy finished"])
        let expectedLine = try fixture.client.requestFrame(invocation)

        // Act
        let outcome = try fixture.handler.handleUnreachableApp(invocation: invocation) { expectedLine }

        // Assert
        #expect(outcome == .queued(reply: "message queued"))
        #expect(try fixture.spooledLines() == [expectedLine])
        #expect(try fixture.notificationFileMode() == 0o600)
        #expect(!expectedLine.contains(fixture.paneToken))
    }

    @Test("needs-you and done queue their own replies while --clear refuses offline")
    func deliberateVariantsFollowDescriptorEligibility() throws {
        // Arrange
        let fixture = try PaneNotificationSpoolFixture()
        defer { fixture.remove() }

        // Act
        let needsYou = try fixture.queue(["needs-you", "approval please"])
        let done = try fixture.queue(["done"])
        let clear = try fixture.queue(["needs-you", "--clear"])

        // Assert
        #expect(needsYou == .queued(reply: "needs-you queued"))
        #expect(done == .queued(reply: "done queued"))
        #expect(clear == .clearUnavailableWhileOffline)
        #expect(try fixture.spooledLines().count == 2)
    }

    @Test("a pane without spool environment keeps the ordinary unreachable failure")
    func missingPaneEnvironmentDoesNotQueue() throws {
        // Arrange
        let fixture = try PaneNotificationSpoolFixture()
        defer { fixture.remove() }
        let handler = PaneNotificationOfflineHandler(environment: [:])
        let invocation = try fixture.invocation(["message", "unaddressed"])

        // Act
        let outcome = try handler.handleUnreachableApp(invocation: invocation) {
            try fixture.client.requestFrame(invocation)
        }

        // Assert
        #expect(outcome == .notQueued)
        #expect(!FileManager.default.fileExists(atPath: fixture.location.notificationFileURL.path))
    }

    @Test("an unwritable spool directory fails explicitly and never claims a queued notification")
    func unwritableDirectoryFailsWithoutClaimingQueued() throws {
        // Arrange
        let fixture = try PaneNotificationSpoolFixture()
        defer { fixture.restorePermissions() }
        defer { fixture.remove() }
        try fixture.makeSpoolDirectoryReadOnly()
        let invocation = try fixture.invocation(["message", "unwritable"])

        // Act
        let failure = #expect(throws: PaneNotificationSpoolWriteError.self) {
            _ = try fixture.handler.handleUnreachableApp(invocation: invocation) {
                try fixture.client.requestFrame(invocation)
            }
        }

        // Assert
        #expect(failure?.reason == .notificationFileUnavailable)
        #expect(!FileManager.default.fileExists(atPath: fixture.location.notificationFileURL.path))
    }

    @Test("concurrent writers leave two intact lines under the exclusive lock")
    func concurrentWritersProduceIntactLines() async throws {
        // Arrange
        let fixture = try PaneNotificationSpoolFixture()
        defer { fixture.remove() }
        let first = try fixture.invocation(["message", String(repeating: "a", count: 4096)])
        let second = try fixture.invocation(["message", String(repeating: "b", count: 4096)])
        let firstLine = try fixture.client.requestFrame(first)
        let secondLine = try fixture.client.requestFrame(second)
        let writer = PaneNotificationSpoolWriter()
        let location = fixture.location

        // Act
        async let firstAppend: Void = Self.append(writer, firstLine, location)
        async let secondAppend: Void = Self.append(writer, secondLine, location)
        _ = try await (firstAppend, secondAppend)

        // Assert
        #expect(try Set(fixture.spooledLines()) == Set([firstLine, secondLine]))
    }

    /// The drain replaces a partially drained spool file by renaming a
    /// replacement over the path. `flock` holds an open file description rather
    /// than a name, so a writer that opened before that rename wakes up holding
    /// an exclusive lock on an inode with no directory entry. Writing there
    /// succeeds, synchronizes, and is never read by anyone: the queued reply the
    /// CLI already gave the model would be a lie.
    ///
    /// Whichever way the two orderings fall, the line has to end up in the file
    /// the path names, alongside the replacement's own line.
    @Test("an append racing a spool file replacement lands in the file the path names")
    func appendRacingAReplacementLandsInTheSurvivingFile() async throws {
        // Arrange: a spooled line, a replacement to rename over it, and the
        // exclusive lock held the way a drain holds it.
        let fixture = try PaneNotificationSpoolFixture()
        defer { fixture.remove() }
        let existing = try fixture.invocation(["message", "already spooled"])
        _ = try fixture.handler.handleUnreachableApp(invocation: existing) {
            try fixture.client.requestFrame(existing)
        }
        let racing = try fixture.invocation(["message", "raced the replacement"])
        let racingLine = try fixture.client.requestFrame(racing)
        let retainedLine = try fixture.client.requestFrame(
            try fixture.invocation(["message", "retained by the drain"]))
        let location = fixture.location
        let heldLock = try fixture.holdExclusiveLock()

        // Act: the append blocks in `flock` until the lock is released, so the
        // replacement lands while it is waiting. This suite is nonisolated, so
        // the task carries no isolation for the blocking call to inherit.
        let append = Task {
            try PaneNotificationSpoolWriter().append(
                requestLine: racingLine, to: location, maximumLineBytes: 1_048_576)
        }
        for _ in 0..<200 { await Task.yield() }
        let replacementInode = try fixture.replaceNotificationFile(withLines: [retainedLine])
        heldLock.release()
        try await append.value

        // Assert
        #expect(try fixture.spooledLines() == [retainedLine, racingLine])
        #expect(try fixture.notificationFileInode() == replacementInode)
    }

    @Test("a missing socket path and a refused connection both permit queuing")
    func unreachableEndpointsPermitQueuing() throws {
        // Arrange
        let fixture = try PaneNotificationSpoolFixture()
        defer { fixture.remove() }
        let invocation = try fixture.invocation(["message", "unreachable"])
        let refusedPath = try makeBoundButUnlistenedSocketPath()
        defer { unlink(refusedPath) }
        let refusedClient = AgentStudioIPCClient(
            configuration: .init(socketPath: refusedPath),
            descriptors: fixture.descriptors
        )
        // A short path: `sun_path` is 104 bytes, and a temporary-directory
        // socket name long enough to overflow it never reaches `connect`.
        let missingPathClient = AgentStudioIPCClient(
            configuration: .init(socketPath: temporaryIPCDescriptorClientSocketPath()),
            descriptors: fixture.descriptors
        )

        // Act
        let missingPathFailure = try captureIPCDescriptorClientFailure {
            _ = try missingPathClient.call(invocation, requestID: 1)
        }
        let refusedFailure = try captureIPCDescriptorClientFailure {
            _ = try refusedClient.call(invocation, requestID: 1)
        }

        // Assert
        #expect(missingPathFailure.permitsOfflineQueue)
        #expect(refusedFailure.permitsOfflineQueue)
    }

    @Test("an authentication rejection from a live app never permits queuing")
    func authenticationRejectionNeverQueues() throws {
        // Arrange
        let fixture = try PaneNotificationSpoolFixture()
        defer { fixture.remove() }
        let endpoint = UnixSocketEndpoint(path: temporaryIPCDescriptorClientSocketPath())
        let listener = UnixSocketListener(endpoint: endpoint)
        try listener.start { connection in
            var decoder = NDJSONFrameDecoder(maxFrameBytes: 65_536)
            let request = try receiveIPCDescriptorClientRequest(connection: connection, decoder: &decoder)
            try connection.send(
                try makeIPCDescriptorClientResponseFrame(
                    id: request.id, result: IPCAuthStatusResult.unauthenticated))
            connection.close()
        }
        defer { listener.stop() }
        let invocation = try fixture.invocation(["message", "rejected"])
        let client = AgentStudioIPCClient(
            configuration: .init(
                socketPath: endpoint.path, authToken: fixture.paneToken, maxRequestFrameBytes: 65_536),
            descriptors: fixture.descriptors + [try IPCDescriptorClientFixtureCatalog.make().authentication]
        )

        // Act
        let failure = try captureIPCDescriptorClientFailure {
            _ = try client.call(invocation, requestID: 1)
        }

        // Assert
        #expect(failure.disposition == .authenticationRejected)
        #expect(!failure.permitsOfflineQueue)
        #expect(!FileManager.default.fileExists(atPath: fixture.location.notificationFileURL.path))
    }

    /// A socket file that no process is accepting on is the stale-socket case:
    /// `connect` refuses instead of reporting an absent path.
    private func makeBoundButUnlistenedSocketPath() throws -> String {
        let path = temporaryIPCDescriptorClientSocketPath()
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        try #require(pathBytes.count < MemoryLayout.size(ofValue: address.sun_path))
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                bind(descriptor, rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try #require(bindResult == 0)
        return path
    }

    private static func append(
        _ writer: PaneNotificationSpoolWriter,
        _ line: String,
        _ location: PaneNotificationSpoolLocation
    ) async throws {
        try await Task {
            try writer.append(requestLine: line, to: location, maximumLineBytes: 1_048_576)
        }.value
    }
}

private enum PaneNotificationSpoolFixtureError: Error {
    case exclusiveLockUnavailable
    case replacementFailed
}

/// An exclusive `flock` the fixture holds until it says otherwise.
private final class HeldNotificationFileLock: @unchecked Sendable {
    private var descriptor: Int32?

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    func release() {
        guard let descriptor else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        self.descriptor = nil
    }
}

private struct PaneNotificationSpoolFixture {
    let rootDirectory: URL
    let location: PaneNotificationSpoolLocation
    let handler: PaneNotificationOfflineHandler
    let client: AgentStudioIPCClient
    let descriptors: [IPCAnyMethodDescriptor]
    let absentSocketPath: String
    let paneToken = "PANE-TOKEN-NEVER-SPOOLED"

    init() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-spool-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let paneIdentifier = UUIDv7.generate()
        let spoolDirectory = rootDirectory.appending(path: "spool/v2")
        location = PaneNotificationSpoolLocation(
            spoolDirectory: spoolDirectory,
            paneIdentifier: paneIdentifier
        )
        handler = PaneNotificationOfflineHandler(
            environment: [
                "AGENTSTUDIO_IPC_SPOOL_DIR": spoolDirectory.path,
                "AGENTSTUDIO_PANE_ID": paneIdentifier.uuidString,
            ]
        )
        descriptors = try IPCBuiltInMethodCatalog.offlineNotificationDescriptors(
            examples: .init(illustrativeIdentifier: UUIDv7.generate())
        )
        absentSocketPath = rootDirectory.appending(path: "absent.sock").path
        client = AgentStudioIPCClient(
            configuration: .init(socketPath: absentSocketPath, authToken: paneToken),
            descriptors: descriptors
        )
    }

    func invocation(_ arguments: [String]) throws -> IPCDescriptorInvocation {
        try IPCDescriptorInvocationParser.parse(
            arguments,
            descriptors: descriptors,
            correlationIDGenerator: { UUIDv7.generate() }
        )
    }

    func queue(_ arguments: [String]) throws -> PaneNotificationOfflineOutcome {
        let invocation = try invocation(arguments)
        return try handler.handleUnreachableApp(invocation: invocation) {
            try client.requestFrame(invocation)
        }
    }

    func spooledLines() throws -> [String] {
        let contents = try String(contentsOf: location.notificationFileURL, encoding: .utf8)
        return contents.split(separator: "\n").map(String.init)
    }

    /// The same exclusive lock the drain takes across a whole file rewrite.
    func holdExclusiveLock() throws -> HeldNotificationFileLock {
        let descriptor = open(location.notificationFileURL.path, O_RDWR)
        guard descriptor >= 0, flock(descriptor, LOCK_EX) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            throw PaneNotificationSpoolFixtureError.exclusiveLockUnavailable
        }
        return HeldNotificationFileLock(descriptor: descriptor)
    }

    /// Replaces the spool file exactly the way a partial drain does, and answers
    /// with the inode the path names afterwards.
    func replaceNotificationFile(withLines lines: [String]) throws -> ino_t {
        let temporaryURL = location.spoolDirectory.appendingPathComponent(
            "replacement-\(UUIDv7.generate().uuidString).partial")
        try Data(lines.map { "\($0)\n" }.joined().utf8).write(to: temporaryURL)
        guard rename(temporaryURL.path, location.notificationFileURL.path) == 0 else {
            throw PaneNotificationSpoolFixtureError.replacementFailed
        }
        return try notificationFileInode()
    }

    func notificationFileInode() throws -> ino_t {
        var status = stat()
        guard stat(location.notificationFileURL.path, &status) == 0 else {
            throw PaneNotificationSpoolFixtureError.replacementFailed
        }
        return status.st_ino
    }

    func notificationFileMode() throws -> mode_t {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: location.notificationFileURL.path
        )
        return (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
    }

    func makeSpoolDirectoryReadOnly() throws {
        try FileManager.default.createDirectory(
            at: location.spoolDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o500]
        )
    }

    func restorePermissions() {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: location.spoolDirectory.path
        )
    }

    func remove() {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: location.spoolDirectory.path
        )
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
