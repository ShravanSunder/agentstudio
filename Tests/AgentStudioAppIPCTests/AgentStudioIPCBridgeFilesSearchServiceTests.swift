import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio IPC Bridge Files search", .serialized)
struct AgentStudioIPCBridgeFilesSearchServiceTests {
    @Test("bridge.files.search reads a Bridge pane's collection with defaulted scope and limit")
    func searchReadsBridgeCollection() throws {
        // Arrange
        let paneId = UUID()
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            panes: [makePaneSummary(id: paneId, ordinal: 1, contentKind: .bridgePanel)]
        )
        defer { fixture.cleanup() }
        try fixture.server.start()

        // Act
        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(94),
                method: "bridge.files.search",
                params: .object(["handle": .string("pane:1"), "searchText": .string("App")])
            )
        )

        // Assert
        #expect(response.id == .number(94))
        #expect(response.error == nil)
        let result = try decodeResponseResult(IPCBridgeFilesSearchResult.self, from: response)
        #expect(result.paneId == paneId)
        #expect(result.status == .results)
        #expect(result.matches.map(\.memberWorktreeId) == [nil])
        #expect(result.complete)
    }

    @Test("bridge.files.search rejects a member scope without its worktree as invalid params")
    func memberScopeWithoutWorktreeIsInvalid() throws {
        // Arrange
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            panes: [makePaneSummary(id: UUID(), ordinal: 1, contentKind: .bridgePanel)]
        )
        defer { fixture.cleanup() }
        try fixture.server.start()

        // Act
        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(95),
                method: "bridge.files.search",
                params: .object([
                    "handle": .string("pane:1"),
                    "searchText": .string("App"),
                    "scope": .string("member"),
                ])
            )
        )

        // Assert
        #expect(response.id == .number(95))
        #expect(response.error?.code == -32_602)
        #expect(response.result == nil)
    }
}
