import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio IPC Bridge service", .serialized)
struct AgentStudioIPCBridgeServiceTests {
    @Test("debug unsafe no-auth refreshes Bridge diff package")
    func debugUnsafeNoAuthRefreshesBridgeDiffPackage() throws {
        let paneId = UUID()
        let correlationId = UUID()
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            panes: [makePaneSummary(id: paneId, ordinal: 1, contentKind: .bridgePanel)]
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(65),
                method: "bridge.diff.refresh",
                params: .object([
                    "handle": .string("pane:1"),
                    "correlationId": .string(correlationId.uuidString),
                ])
            )
        )

        #expect(response.id == .number(65))
        #expect(response.error == nil)
        let result = try decodeResponseResult(IPCBridgeReviewRefreshResult.self, from: response)
        #expect(result.paneId == paneId)
        #expect(result.refreshed == true)
        #expect(result.status == "ready")
        #expect(result.packageId == "package-test")
        #expect(result.correlationId == correlationId)
    }

    @Test("debug unsafe no-auth serves Bridge package and file view content methods")
    func debugUnsafeNoAuthServesBridgePackageAndFileViewContentMethods() throws {
        let paneId = UUID()
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            panes: [makePaneSummary(id: paneId, ordinal: 1, contentKind: .bridgePanel)]
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let packageResponse = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(66),
                method: "bridge.diff.getPackage",
                params: .object(["handle": .string("pane:1")])
            )
        )

        #expect(packageResponse.id == .number(66))
        #expect(packageResponse.error == nil)
        let package = try decodeResponseResult(IPCBridgeReviewPackageResult.self, from: packageResponse)
        let firstItem = try #require(package.package?.items.first)
        let headHandle = try #require(firstItem.contentRoles.head)
        #expect(package.paneId == paneId)
        #expect(firstItem.headPath == "Sources/App/View.swift")

        let contentResponse = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(67),
                method: "bridge.fileView.getContent",
                params: .object([
                    "handle": .string("pane:1"),
                    "contentHandleId": .string(headHandle.handleId),
                    "reviewGeneration": .number(Double(headHandle.reviewGeneration)),
                ])
            )
        )

        #expect(contentResponse.id == .number(67))
        #expect(contentResponse.error == nil)
        let content = try decodeResponseResult(IPCBridgeContentGetResult.self, from: contentResponse)
        #expect(content.paneId == paneId)
        #expect(content.handle.handleId == headHandle.handleId)
        #expect(content.contentText == "let value = 1\n")
    }

    @Test("debug unsafe no-auth serves Bridge render state method")
    func debugUnsafeNoAuthServesBridgeRenderStateMethod() throws {
        let paneId = UUID()
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            panes: [makePaneSummary(id: paneId, ordinal: 1, contentKind: .bridgePanel)]
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(71),
                method: "bridge.diff.renderState",
                params: .object(["handle": .string("pane:1")])
            )
        )

        #expect(response.id == .number(71))
        #expect(response.error == nil)
        let renderState = try decodeResponseResult(IPCBridgeRenderStateResult.self, from: response)
        #expect(renderState.paneId == paneId)
        #expect(renderState.summary.hasReviewShell)
        #expect(renderState.summary.sidebarPosition == "right")
        #expect(renderState.diagnostics.evaluateSucceeded)
        #expect(renderState.diagnostics.pageErrorCount == 0)
        #expect(renderState.diagnostics.pageErrorKinds.isEmpty)
    }

    @Test("spawned pane agents cannot open new Bridge review panes")
    func spawnedPaneAgentsCannotOpenNewBridgeReviewPanes() throws {
        let paneId = UUID()
        let fixture = try LiveServerFixture(
            panes: [makePaneSummary(id: paneId, ordinal: 1, contentKind: .bridgePanel)]
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()
        let principal = IPCPrincipal(
            principalId: UUID(),
            runtimeId: fixture.runtimeId,
            accessMode: .agentStudioOnly,
            kind: .spawnedPaneAgent(boundPaneId: paneId.uuidString, boundWorkspaceId: nil),
            approvalAuthority: .noApprovalAuthority
        )
        let token = try fixture.server.principalRegistry.issueSubjectToken(for: principal)
        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path)
        )
        defer {
            connection.close()
        }
        var frameReader = TestFrameReader()
        try login(connection: connection, token: token, requestId: 71, reader: &frameReader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(72),
                method: "bridge.diff.load",
                params: .object([
                    "target": .string("pane:active")
                ])
            )
        )

        let response = try frameReader.receiveResponse(connection: connection)
        #expect(response.error?.code == -32_002)
        #expect(response.error?.message == "unauthorized")
    }

    @Test("Bridge select publishes notification for the bound pane subscriber")
    func bridgeSelectPublishesNotificationForBoundPaneSubscriber() throws {
        let paneId = UUID()
        let fixture = try LiveServerFixture(
            panes: [makePaneSummary(id: paneId, ordinal: 1, contentKind: .bridgePanel)]
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()
        let principal = IPCPrincipal(
            principalId: UUID(),
            runtimeId: fixture.runtimeId,
            accessMode: .agentStudioOnly,
            kind: .spawnedPaneAgent(boundPaneId: paneId.uuidString, boundWorkspaceId: nil),
            approvalAuthority: .noApprovalAuthority
        )
        let token = try fixture.server.principalRegistry.issueSubjectToken(for: principal)
        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path)
        )
        defer {
            connection.close()
        }
        var frameReader = TestFrameReader()

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(68),
                method: "auth.login",
                params: .object(["token": .string(token.rawValue)])
            )
        )
        _ = try frameReader.receiveResponse(connection: connection)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(69),
                method: "events.subscribe",
                params: .object([
                    "eventNames": .array([.string(IPCEventName.bridgeFileSelected.rawValue)])
                ])
            )
        )
        _ = try frameReader.receiveResponse(connection: connection)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(70),
                method: "bridge.diff.selectFile",
                params: .object([
                    "handle": .string("pane:1"),
                    "itemId": .string("item-source"),
                ])
            )
        )

        let frames = [
            try frameReader.receiveFrame(connection: connection),
            try frameReader.receiveFrame(connection: connection),
        ]
        let notificationFrame = try #require(frames.first { $0.contains("events.notification") })
        let notificationObject = try #require(
            try JSONSerialization.jsonObject(with: Data(notificationFrame.utf8)) as? [String: Any]
        )
        let params = try #require(notificationObject["params"] as? [String: Any])
        let payload = try #require(params["payload"] as? [String: Any])
        let bridgePayload = try #require(payload["bridge"] as? [String: Any])

        #expect(params["name"] as? String == IPCEventName.bridgeFileSelected.rawValue)
        #expect(bridgePayload["paneId"] as? String == paneId.uuidString)
        #expect(bridgePayload["itemId"] as? String == "item-source")
    }
}
