import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

@Suite("AgentStudio App IPC sidebar service", .serialized)
struct AgentStudioAppIPCSidebarServiceTests {
    @Test("debug token automation can switch sidebar grouping and surface")
    func debugTokenAutomationCanSwitchSidebarGroupingAndSurface() throws {
        let fixture = try LiveServerFixture(
            channel: .debug,
            sidebarPort: FakeSidebarPort(),
            debugTokenEscrowEnabled: true
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let connection = try authenticatedConnection(for: fixture, tokenRequestId: 67)
        defer {
            connection.close()
        }
        var reader = TestFrameReader()

        let repoSetResult = try setGrouping(
            connection: connection,
            reader: &reader,
            requestId: 68,
            surface: .repo,
            mode: .pane
        )
        #expect(repoSetResult.surface == .repo)
        #expect(repoSetResult.mode == .pane)

        let inboxSetResult = try setGrouping(
            connection: connection,
            reader: &reader,
            requestId: 69,
            surface: .inbox,
            mode: .noGrouping
        )
        #expect(inboxSetResult.surface == .inbox)
        #expect(inboxSetResult.mode == .noGrouping)

        let surfaceSetResult = try setSurface(
            connection: connection,
            reader: &reader,
            requestId: 70,
            surface: .inbox
        )
        #expect(surfaceSetResult.surface == .inbox)

        let surfaceGetResult = try getSurface(
            connection: connection,
            reader: &reader,
            requestId: 71
        )
        #expect(surfaceGetResult.surface == .inbox)
    }

    @Test("debug unsafe no-auth denies sidebar semantic methods")
    func debugUnsafeNoAuthDeniesSidebarSemanticMethods() throws {
        let fixture = try LiveServerFixture(accessMode: .unsafeDebug, channel: .debug)
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(72),
                method: "sidebar.grouping.set",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCSidebarGroupingSetParams(surface: .repo, mode: .tab)
                )
            )
        )

        #expect(response.id == .number(72))
        #expect(response.error?.code == -32_002)
        #expect(response.error?.message == "unauthorized")
    }

    @Test("sidebar rejects repo none grouping before mutation")
    func sidebarRejectsRepoNoneGroupingBeforeMutation() throws {
        let fixture = try LiveServerFixture(
            channel: .debug,
            debugTokenEscrowEnabled: true
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let connection = try authenticatedConnection(for: fixture, tokenRequestId: 73)
        defer {
            connection.close()
        }
        var reader = TestFrameReader()

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(74),
                method: "sidebar.grouping.set",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCSidebarGroupingSetParams(surface: .repo, mode: .noGrouping)
                )
            )
        )
        let rejected = try reader.receiveResponse(connection: connection)
        #expect(rejected.error?.code == -32_007)
        #expect(rejected.error?.message == "validation rejected")

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(75),
                method: "sidebar.grouping.get",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCSidebarGroupingGetParams(surface: .repo)
                )
            )
        )
        let current = try reader.receiveResponse(connection: connection)
        #expect(current.error == nil)
        let currentResult = try decodeResponseResult(IPCSidebarGroupingResult.self, from: current)
        #expect(currentResult.mode == .repo)
    }

    private func authenticatedConnection(
        for fixture: LiveServerFixture,
        tokenRequestId: Int
    ) throws -> UnixSocketConnection {
        let token = AgentStudioIPCSubjectToken(
            rawValue: try String(contentsOf: fixture.paths.debugTokenURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        var reader = TestFrameReader()
        try login(connection: connection, token: token, requestId: tokenRequestId, reader: &reader)
        return connection
    }

    private func setGrouping(
        connection: UnixSocketConnection,
        reader: inout TestFrameReader,
        requestId: Int,
        surface: IPCSidebarSurface,
        mode: IPCSidebarGroupingMode
    ) throws -> IPCSidebarGroupingResult {
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(requestId),
                method: "sidebar.grouping.set",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCSidebarGroupingSetParams(surface: surface, mode: mode)
                )
            )
        )
        let response = try reader.receiveResponse(connection: connection)
        #expect(response.error == nil)
        return try decodeResponseResult(IPCSidebarGroupingResult.self, from: response)
    }

    private func setSurface(
        connection: UnixSocketConnection,
        reader: inout TestFrameReader,
        requestId: Int,
        surface: IPCSidebarSurface
    ) throws -> IPCSidebarSurfaceResult {
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(requestId),
                method: "sidebar.surface.set",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCSidebarSurfaceSetParams(surface: surface)
                )
            )
        )
        let response = try reader.receiveResponse(connection: connection)
        #expect(response.error == nil)
        return try decodeResponseResult(IPCSidebarSurfaceResult.self, from: response)
    }

    private func getSurface(
        connection: UnixSocketConnection,
        reader: inout TestFrameReader,
        requestId: Int
    ) throws -> IPCSidebarSurfaceResult {
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(requestId),
                method: "sidebar.surface.get",
                params: try JSONRPCCodec.encodeJSONValue(IPCSidebarSurfaceGetParams())
            )
        )
        let response = try reader.receiveResponse(connection: connection)
        #expect(response.error == nil)
        return try decodeResponseResult(IPCSidebarSurfaceResult.self, from: response)
    }
}
