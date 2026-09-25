import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

/// Pane agents reach their receiving Bridge through the real server, registry
/// and pane credentials on the stable channel: `self` from a terminal or a
/// drawer terminal is admitted and hands the Bridge port the agent's own-pane
/// assertion; another terminal is refused by name; a receiver with no mounted
/// page answers `notMounted`.
@Suite("AgentStudio IPC Bridge agent reach", .serialized)
struct AgentStudioIPCBridgeAgentReachServiceTests {
    @Test("a terminal agent searches its own Bridge through self")
    func terminalAgentReachesOwnBridgeThroughSelf() async throws {
        // Arrange
        let terminalId = UUID()
        let recorder = BridgeFilesSearchInvocationRecorder()
        let fixture = try LiveServerFixture(
            channel: .stable,
            panes: [makePaneSummary(id: terminalId, ordinal: 1, contentKind: .terminal)],
            bridgePort: FakeBridgePort(paneId: terminalId, filesSearchRecorder: recorder)
        )
        defer { fixture.cleanup() }

        // Act
        let response = try await searchAsAgent(fixture: fixture, agentPaneId: terminalId, handle: "self")

        // Assert
        #expect(response.error == nil)
        let result = try decodeResponseResult(IPCBridgeFilesSearchResult.self, from: response)
        #expect(result.status == .results)
        let invocations = recorder.snapshot()
        #expect(invocations.count == 1)
        #expect(invocations.first?.boundPaneId == terminalId)
        #expect(invocations.first?.handle.contains(terminalId.uuidString) == true)
    }

    @Test("a drawer terminal agent searches its own receiving Bridge through self")
    func drawerTerminalAgentReachesThroughSelf() async throws {
        // Arrange
        let ownerTerminalId = UUID()
        let drawerTerminalId = UUID()
        let recorder = BridgeFilesSearchInvocationRecorder()
        let fixture = try LiveServerFixture(
            channel: .stable,
            panes: [
                makePaneSummary(id: ownerTerminalId, ordinal: 1, contentKind: .terminal),
                makePaneSummary(id: drawerTerminalId, ordinal: 2, contentKind: .terminal),
            ],
            bridgePort: FakeBridgePort(paneId: ownerTerminalId, filesSearchRecorder: recorder),
            ownPaneScopes: [
                AppIPCOwnPaneScope(boundPaneId: drawerTerminalId, isDrawerTerminal: true, drawerChildPaneIds: [])
            ]
        )
        defer { fixture.cleanup() }

        // Act
        let response = try await searchAsAgent(fixture: fixture, agentPaneId: drawerTerminalId, handle: "self")

        // Assert
        #expect(response.error == nil)
        #expect(recorder.snapshot().map(\.boundPaneId) == [drawerTerminalId])
    }

    @Test("another terminal's handle is refused by name before the Bridge is asked")
    func anotherTerminalIsRefused() async throws {
        // Arrange
        let terminalId = UUID()
        let otherTerminalId = UUID()
        let recorder = BridgeFilesSearchInvocationRecorder()
        let fixture = try LiveServerFixture(
            channel: .stable,
            panes: [
                makePaneSummary(id: terminalId, ordinal: 1, contentKind: .terminal),
                makePaneSummary(id: otherTerminalId, ordinal: 2, contentKind: .terminal),
            ],
            bridgePort: FakeBridgePort(paneId: terminalId, filesSearchRecorder: recorder)
        )
        defer { fixture.cleanup() }

        // Act
        let response = try await searchAsAgent(
            fixture: fixture, agentPaneId: terminalId, handle: otherTerminalId.uuidString)

        // Assert
        #expect(response.error?.code == -32_011)
        #expect(
            response.error?.data
                == .object(["reason": .string("notYetAllowed"), "name": .string("bridge.files.search")]))
        #expect(recorder.snapshot().isEmpty)
    }

    @Test("an unmounted receiver answers notMounted to its own agent")
    func unmountedReceiverAnswersNotMounted() async throws {
        // Arrange
        let terminalId = UUID()
        let fixture = try LiveServerFixture(
            channel: .stable,
            panes: [makePaneSummary(id: terminalId, ordinal: 1, contentKind: .terminal)],
            bridgePort: FakeBridgePort(
                paneId: terminalId, filesSearchFailure: AppIPCBridgeError(reason: .notMounted))
        )
        defer { fixture.cleanup() }

        // Act
        let response = try await searchAsAgent(fixture: fixture, agentPaneId: terminalId, handle: "self")

        // Assert
        #expect(response.error?.code == -32_005)
        #expect(response.error?.message == "bridge not mounted")
        #expect(response.error?.data == .object(["reason": .string("notMounted")]))
    }

    private func searchAsAgent(
        fixture: LiveServerFixture,
        agentPaneId: UUID,
        handle: String
    ) async throws -> JSONRPCResponseMessage {
        try fixture.server.start()
        let token = try fixture.issueTestCredential(
            for: .pane(paneId: agentPaneId, credentialRecordId: UUIDv7.generate(), status: .registered)
        )
        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path)
        )
        defer { connection.close() }
        var frameReader = TestFrameReader()
        try await loginWithoutBlockingMainActor(
            connection: connection,
            token: token,
            requestId: 1,
            reader: &frameReader
        )
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(2),
                method: "bridge.files.search",
                params: .object(["handle": .string(handle), "searchText": .string("plan")])
            )
        )
        return try await frameReader.receiveResponseWithoutBlockingMainActor(connection: connection)
    }
}
