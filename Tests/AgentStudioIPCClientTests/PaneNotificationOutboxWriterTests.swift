import AgentStudioCLIStore
import AgentStudioIPCTransport
import AgentStudioPrimitives
import AgentStudioProgrammaticControl
import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudioIPCClientCore

#if canImport(Darwin)
    import Darwin
#endif

@Suite("Offline pane notification outbox writer")
struct PaneNotificationOutboxWriterTests {
    @Test("an eligible message stores the exact wire envelope in an owner-only SQLite file")
    func eligibleMessageAppendsTheWireEnvelope() async throws {
        try await valueFromDedicatedThread {
            let fixture = try PaneNotificationOutboxFixture()
            defer { fixture.remove() }
            let invocation = try fixture.invocation(["message", "deploy finished"])
            let expectedLine = try fixture.client.requestFrame(invocation)
            let parameters = try JSONDecoder().decode(
                IPCSessionMessageParams.self, from: invocation.normalizedParameters.data)

            let outcome = try fixture.handler.handleUnreachableApp(invocation: invocation) { expectedLine }

            #expect(outcome == .queued(reply: "message queued"))
            let entries = try fixture.entries()
            #expect(entries.count == 1)
            if let entry = entries.first, case .notice(let notice) = entry {
                #expect(notice.payloadJSON == expectedLine)
                #expect(notice.messageID == parameters.correlationId)
                #expect(notice.paneID == fixture.paneID)
            }
            #expect(try fixture.storeFileMode() == 0o600)
            #expect(!expectedLine.contains(fixture.paneToken))
            #expect(!FileManager.default.fileExists(atPath: fixture.legacyDirectory.path))
        }
    }

    @Test("needs-you and done queue their own replies while clear refuses offline")
    func deliberateVariantsFollowDescriptorEligibility() async throws {
        try await valueFromDedicatedThread {
            let fixture = try PaneNotificationOutboxFixture()
            defer { fixture.remove() }

            let needsYou = try fixture.queue(["needs-you", "approval please"])
            let done = try fixture.queue(["done"])
            let clear = try fixture.queue(["needs-you", "--clear"])

            #expect(needsYou == .queued(reply: "needs-you queued"))
            #expect(done == .queued(reply: "done queued"))
            #expect(clear == .clearUnavailableWhileOffline)
            #expect(try fixture.entries().count == 2)
        }
    }

    @Test("a pane without store environment keeps the ordinary unreachable failure")
    func missingPaneEnvironmentDoesNotQueue() async throws {
        try await valueFromDedicatedThread {
            let fixture = try PaneNotificationOutboxFixture()
            defer { fixture.remove() }
            let handler = PaneNotificationOfflineHandler(environment: [:])
            let invocation = try fixture.invocation(["message", "unaddressed"])

            let outcome = try handler.handleUnreachableApp(invocation: invocation) {
                try fixture.client.requestFrame(invocation)
            }

            #expect(outcome == .notQueued)
            #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path))
        }
    }

    @Test("a missing or unknown store channel never defaults to stable", arguments: ["", "unknown-channel"])
    func missingOrUnknownChannelDoesNotQueue(channel: String) async throws {
        try await valueFromDedicatedThread {
            let fixture = try PaneNotificationOutboxFixture()
            defer { fixture.remove() }
            var environment = fixture.environment
            environment["AGENTSTUDIO_CLI_STORE_CHANNEL"] = channel.isEmpty ? nil : channel
            let handler = PaneNotificationOfflineHandler(environment: environment)
            let invocation = try fixture.invocation(["message", "channel unavailable"])

            let outcome = try handler.handleUnreachableApp(invocation: invocation) {
                try fixture.client.requestFrame(invocation)
            }

            #expect(outcome == .notQueued)
            #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path))
        }
    }

    @Test("an unwritable store fails explicitly without claiming a queued notification")
    func unwritableStoreFailsWithoutClaimingQueued() async throws {
        try await valueFromDedicatedThread {
            let fixture = try PaneNotificationOutboxFixture()
            defer { fixture.remove() }
            try fixture.makeStoreDirectoryReadOnly()
            defer { fixture.restorePermissions() }
            let invocation = try fixture.invocation(["message", "unwritable"])

            #expect(throws: CLIStoreFailure.unavailable) {
                _ = try fixture.handler.handleUnreachableApp(invocation: invocation) {
                    try fixture.client.requestFrame(invocation)
                }
            }

            #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path))
        }
    }

    @Test("concurrent writers preserve every durably acknowledged envelope intact")
    func concurrentWritersPreserveAcknowledgedEnvelopes() async throws {
        let fixture = try await valueFromDedicatedThread { try PaneNotificationOutboxFixture() }
        defer { fixture.remove() }
        _ = try await valueFromDedicatedThread { try CLIStore.openWriter(url: fixture.storeURL, channel: .debug).get() }
        let first = try fixture.invocation(["message", String(repeating: "a", count: 4096)])
        let second = try fixture.invocation(["message", String(repeating: "b", count: 4096)])
        let firstLine = try fixture.client.requestFrame(first)
        let secondLine = try fixture.client.requestFrame(second)

        async let firstOutcome = queueOnDedicatedThread(fixture: fixture, invocation: first, line: firstLine)
        async let secondOutcome = queueOnDedicatedThread(fixture: fixture, invocation: second, line: secondLine)
        let outcomes = await [firstOutcome, secondOutcome]

        var acknowledged: [String] = []
        for (outcome, line) in zip(outcomes, [firstLine, secondLine]) {
            switch outcome {
            case .success(.queued): acknowledged.append(line)
            case .failure(.busy): break
            default: Issue.record("A configured writer neither queued nor reported SQLite busy")
            }
        }
        #expect(!acknowledged.isEmpty)
        let expected = Set(acknowledged)
        let expectedCount = acknowledged.count
        try await valueFromDedicatedThread {
            let entries = try fixture.entries()
            let payloads = entries.map { entry in
                switch entry {
                case .notice(let notice): notice.payloadJSON
                }
            }
            #expect(Set(payloads) == expected)
            #expect(payloads.count == expectedCount)
        }
    }

    @Test("a missing socket path and a refused connection both permit queuing")
    func unreachableEndpointsPermitQueuing() async throws {
        try await valueFromDedicatedThread {
            let fixture = try PaneNotificationOutboxFixture()
            defer { fixture.remove() }
            let invocation = try fixture.invocation(["message", "unreachable"])
            let refusedPath = try makeBoundButUnlistenedSocketPath()
            defer { unlink(refusedPath) }
            let refusedClient = AgentStudioIPCClient(
                configuration: .init(socketPath: refusedPath), descriptors: fixture.descriptors)
            let missingClient = AgentStudioIPCClient(
                configuration: .init(socketPath: temporaryIPCDescriptorClientSocketPath()),
                descriptors: fixture.descriptors)

            let missing = try captureIPCDescriptorClientFailure { _ = try missingClient.call(invocation, requestID: 1) }
            let refused = try captureIPCDescriptorClientFailure { _ = try refusedClient.call(invocation, requestID: 1) }

            #expect(missing.permitsOfflineQueue)
            #expect(refused.permitsOfflineQueue)
        }
    }

    @Test("authentication rejection from a live app never permits queuing")
    func authenticationRejectionNeverQueues() async throws {
        try await valueFromDedicatedThread {
            let fixture = try PaneNotificationOutboxFixture()
            defer { fixture.remove() }
            let endpoint = UnixSocketEndpoint(path: temporaryIPCDescriptorClientSocketPath())
            let listener = UnixSocketListener(endpoint: endpoint)
            try listener.start { connection in
                defer { connection.close() }
                var decoder = NDJSONFrameDecoder(maxFrameBytes: 65_536)
                let request = try receiveIPCDescriptorClientRequest(connection: connection, decoder: &decoder)
                try connection.send(
                    try makeIPCDescriptorClientResponseFrame(
                        id: request.id, result: IPCAuthStatusResult.unauthenticated))
            }
            defer { listener.stop() }
            let invocation = try fixture.invocation(["message", "rejected"])
            let client = AgentStudioIPCClient(
                configuration: .init(
                    socketPath: endpoint.path, authToken: fixture.paneToken, maxRequestFrameBytes: 65_536),
                descriptors: fixture.descriptors + [try IPCDescriptorClientFixtureCatalog.make().authentication])

            let rejected = try captureIPCDescriptorClientFailure { _ = try client.call(invocation, requestID: 1) }

            #expect(rejected.disposition == .authenticationRejected)
            #expect(!rejected.permitsOfflineQueue)
            #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path))
        }
    }
}

private func queueOnDedicatedThread(
    fixture: PaneNotificationOutboxFixture, invocation: IPCDescriptorInvocation, line: String
) async -> Result<PaneNotificationOfflineOutcome, CLIStoreFailure> {
    do {
        return .success(
            try await valueFromDedicatedThread {
                try fixture.handler.handleUnreachableApp(invocation: invocation) { line }
            })
    } catch let failure as CLIStoreFailure {
        return .failure(failure)
    } catch {
        Issue.record("Unexpected offline queue error: \(error)")
        return .failure(.unavailable)
    }
}

private func makeBoundButUnlistenedSocketPath() throws -> String {
    let path = temporaryIPCDescriptorClientSocketPath()
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    try #require(descriptor >= 0)
    defer { close(descriptor) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    try #require(pathBytes.count < MemoryLayout.size(ofValue: address.sun_path))
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let bound = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    try #require(bound == 0)
    return path
}

private struct PaneNotificationOutboxFixture: Sendable {
    let rootURL: URL
    let storeURL: URL
    let legacyDirectory: URL
    let paneID = UUIDv7.generate()
    let handler: PaneNotificationOfflineHandler
    let client: AgentStudioIPCClient
    let descriptors: [IPCAnyMethodDescriptor]
    let paneToken = "PANE-TOKEN-NEVER-RECORDED"

    var environment: [String: String] {
        [
            "AGENTSTUDIO_CLI_STORE": storeURL.path, "AGENTSTUDIO_CLI_STORE_CHANNEL": "debug",
            "AGENTSTUDIO_PANE_ID": paneID.uuidString,
        ]
    }

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appending(path: "notification-outbox-\(UUIDv7.generate())")
        storeURL = rootURL.appending(path: "ipc/cli.sqlite")
        legacyDirectory = rootURL.appending(path: "ipc/spool/v2")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        descriptors = try IPCBuiltInMethodCatalog.offlineNotificationDescriptors(
            examples: .init(illustrativeIdentifier: UUIDv7.generate()))
        client = AgentStudioIPCClient(
            configuration: .init(socketPath: rootURL.appending(path: "absent.sock").path, authToken: paneToken),
            descriptors: descriptors)
        handler = PaneNotificationOfflineHandler(environment: [
            "AGENTSTUDIO_CLI_STORE": storeURL.path, "AGENTSTUDIO_CLI_STORE_CHANNEL": "debug",
            "AGENTSTUDIO_PANE_ID": paneID.uuidString,
        ])
    }

    func invocation(_ arguments: [String]) throws -> IPCDescriptorInvocation {
        try IPCDescriptorInvocationParser.parse(
            arguments, descriptors: descriptors, correlationIDGenerator: { UUIDv7.generate() })
    }

    func queue(_ arguments: [String]) throws -> PaneNotificationOfflineOutcome {
        let invocation = try invocation(arguments)
        return try handler.handleUnreachableApp(invocation: invocation) { try client.requestFrame(invocation) }
    }

    func entries() throws -> [CLIOutboxEntry] {
        try CLIStore.openReader(url: storeURL, expectedChannel: .debug).get().readOutbox(after: 0).get().entries
    }

    func storeFileMode() throws -> UInt16 {
        let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        return (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
    }

    func makeStoreDirectoryReadOnly() throws {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o500])
    }

    func restorePermissions() {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: storeURL.deletingLastPathComponent().path)
    }

    func remove() {
        restorePermissions()
        try? FileManager.default.removeItem(at: rootURL)
    }
}
