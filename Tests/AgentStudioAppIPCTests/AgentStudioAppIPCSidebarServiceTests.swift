import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

@Suite("AgentStudio App IPC sidebar service", .serialized)
struct AgentStudioAppIPCSidebarServiceTests {
    @Test("debug token automation can read sidebar grouping and surface")
    func debugTokenAutomationCanReadSidebarGroupingAndSurface() throws {
        let fixture = try LiveServerFixture(
            channel: .debug,
            sidebarPort: FakeSidebarPort(
                repoGrouping: .pane,
                inboxGrouping: .noGrouping,
                surface: .inbox
            ),
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

        let repoGrouping = try getGrouping(
            connection: connection,
            reader: &reader,
            requestId: 68,
            surface: .repo
        )
        #expect(repoGrouping.surface == .repo)
        #expect(repoGrouping.mode == .pane)

        let inboxGrouping = try getGrouping(
            connection: connection,
            reader: &reader,
            requestId: 69,
            surface: .inbox
        )
        #expect(inboxGrouping.surface == .inbox)
        #expect(inboxGrouping.mode == .noGrouping)

        let surfaceGetResult = try getSurface(
            connection: connection,
            reader: &reader,
            requestId: 70
        )
        #expect(surfaceGetResult.surface == .inbox)
    }

    @Test("removed sidebar write routes are not method registry entries")
    func removedSidebarWriteRoutesAreNotMethodRegistryEntries() throws {
        let fixture = try LiveServerFixture(
            channel: .debug,
            debugTokenEscrowEnabled: true
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let connection = try authenticatedConnection(for: fixture, tokenRequestId: 71)
        defer {
            connection.close()
        }
        var reader = TestFrameReader()

        for (requestId, method, params) in [
            (
                72,
                "sidebar.grouping.set",
                JSONValue.object(["surface": .string("repo"), "mode": .string("tab")])
            ),
            (
                73,
                "sidebar.surface.set",
                JSONValue.object(["surface": .string("inbox")])
            ),
        ] {
            try sendRequest(
                connection: connection,
                request: JSONRPCClientRequest(
                    id: .number(requestId),
                    method: method,
                    params: params
                )
            )
            let response = try reader.receiveResponse(connection: connection)

            #expect(response.id == .number(requestId))
            #expect(response.error?.code == -32_603)
            #expect(response.error?.message == "method not found")
        }
    }

    @Test("debug unsafe no-auth denies sidebar read methods")
    func debugUnsafeNoAuthDeniesSidebarReadMethods() throws {
        let fixture = try LiveServerFixture(accessMode: .unsafeDebug, channel: .debug)
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(74),
                method: "sidebar.grouping.get",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCSidebarGroupingGetParams(surface: .repo)
                )
            )
        )

        #expect(response.id == .number(74))
        #expect(response.error?.code == -32_002)
        #expect(response.error?.message == "unauthorized")
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

    private func getGrouping(
        connection: UnixSocketConnection,
        reader: inout TestFrameReader,
        requestId: Int,
        surface: IPCSidebarSurface
    ) throws -> IPCSidebarGroupingResult {
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(requestId),
                method: "sidebar.grouping.get",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCSidebarGroupingGetParams(surface: surface)
                )
            )
        )
        let response = try reader.receiveResponse(connection: connection)
        #expect(response.error == nil)
        return try decodeResponseResult(IPCSidebarGroupingResult.self, from: response)
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
