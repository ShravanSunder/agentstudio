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

    @Test("debug unsafe no-auth serves Bridge telemetry snapshot method")
    func debugUnsafeNoAuthServesBridgeTelemetrySnapshotMethod() throws {
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
                id: .number(73),
                method: "bridge.telemetry.snapshot",
                params: .object(["handle": .string("pane:1")])
            )
        )

        #expect(response.id == .number(73))
        #expect(response.error == nil)
        let snapshot = try decodeResponseResult(IPCBridgeTelemetrySnapshotResult.self, from: response)
        #expect(snapshot.paneId == paneId)
        #expect(snapshot.recorderAttached)
        #expect(snapshot.traceExportEnabled)
        #expect(snapshot.status == "ready")
        #expect(snapshot.packageId == "package-test")
        #expect(snapshot.selectedItemId == "item-source")
    }

    @Test("debug unsafe no-auth serves semantic Bridge control methods")
    func debugUnsafeNoAuthServesSemanticBridgeControlMethods() throws {
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

        let searchResponse = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(74),
                method: "bridge.fileTree.search",
                params: .object([
                    "handle": .string("pane:1"),
                    "searchText": .string("BridgePaneController"),
                    "correlationId": .string(correlationId.uuidString),
                ])
            )
        )
        let searchResult = try decodeResponseResult(IPCBridgePageControlResult.self, from: searchResponse)
        #expect(searchResult.paneId == paneId)
        #expect(searchResult.method == "bridge.fileTree.search")
        #expect(searchResult.status == "accepted")
        #expect(searchResult.treeSearchText == "BridgePaneController")
        #expect(searchResult.correlationId == correlationId)

        let filterResponse = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(75),
                method: "bridge.fileTree.setFilter",
                params: .object([
                    "handle": .string("pane:1"),
                    "gitStatusFilter": .string("modified"),
                    "fileClassFilter": .string("source"),
                ])
            )
        )
        let filterResult = try decodeResponseResult(IPCBridgePageControlResult.self, from: filterResponse)
        #expect(filterResult.method == "bridge.fileTree.setFilter")
        #expect(filterResult.gitStatusFilter == "modified")
        #expect(filterResult.fileClassFilter == "source")

        let revealResponse = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(76),
                method: "bridge.fileTree.revealPath",
                params: .object([
                    "handle": .string("pane:1"),
                    "path": .string("Sources/App/View.swift"),
                ])
            )
        )
        let revealResult = try decodeResponseResult(IPCBridgePageControlResult.self, from: revealResponse)
        #expect(revealResult.method == "bridge.fileTree.revealPath")
        #expect(revealResult.itemId == "item-source")
        #expect(revealResult.path == "Sources/App/View.swift")

        let markdownResponse = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(77),
                method: "bridge.fileView.showMarkdownPreview",
                params: .object([
                    "handle": .string("pane:1"),
                    "itemId": .string("item-source"),
                ])
            )
        )
        let markdownResult = try decodeResponseResult(IPCBridgePageControlResult.self, from: markdownResponse)
        #expect(markdownResult.method == "bridge.fileView.showMarkdownPreview")
        #expect(markdownResult.itemId == "item-source")
        #expect(markdownResult.renderMode == "markdownPreview")

        let scrollResponse = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(78),
                method: "bridge.diff.scrollToFile",
                params: .object([
                    "handle": .string("pane:1"),
                    "itemId": .string("item-source"),
                ])
            )
        )
        let scrollResult = try decodeResponseResult(IPCBridgePageControlResult.self, from: scrollResponse)
        #expect(scrollResult.method == "bridge.diff.scrollToFile")
        #expect(scrollResult.itemId == "item-source")
    }

    @Test("Bridge methods reject valid non-Bridge pane targets as unsupported")
    func bridgeMethodsRejectValidNonBridgePaneTargetsAsUnsupported() throws {
        let paneId = UUID()
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            panes: [makePaneSummary(id: paneId, ordinal: 1, contentKind: .terminal)]
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let bridgeRequests: [(id: Int, method: String, params: JSONValue)] = [
            (79, "bridge.diff.getPackage", .object(["handle": .string("pane:1")])),
            (80, "bridge.diff.renderState", .object(["handle": .string("pane:1")])),
            (81, "bridge.diff.refresh", .object(["handle": .string("pane:1")])),
            (
                82,
                "bridge.diff.selectFile",
                .object([
                    "handle": .string("pane:1"),
                    "itemId": .string("item-source"),
                ])
            ),
            (
                83,
                "bridge.diff.scrollToFile",
                .object([
                    "handle": .string("pane:1"),
                    "itemId": .string("item-source"),
                ])
            ),
            (
                84,
                "bridge.fileTree.search",
                .object([
                    "handle": .string("pane:1"),
                    "searchText": .string("BridgePaneController"),
                ])
            ),
            (
                85,
                "bridge.fileTree.setFilter",
                .object([
                    "handle": .string("pane:1"),
                    "gitStatusFilter": .string("modified"),
                    "fileClassFilter": .string("source"),
                ])
            ),
            (
                86,
                "bridge.fileTree.revealPath",
                .object([
                    "handle": .string("pane:1"),
                    "path": .string("Sources/App/View.swift"),
                ])
            ),
            (
                87,
                "bridge.fileView.showMarkdownPreview",
                .object([
                    "handle": .string("pane:1"),
                    "itemId": .string("item-source"),
                ])
            ),
            (
                88,
                "bridge.fileView.getContent",
                .object([
                    "handle": .string("pane:1"),
                    "contentHandleId": .string("content-head"),
                    "reviewGeneration": .number(1),
                ])
            ),
            (89, "bridge.telemetry.snapshot", .object(["handle": .string("pane:1")])),
            (90, "bridge.telemetry.flush", .object(["handle": .string("pane:1")])),
        ]

        for bridgeRequest in bridgeRequests {
            let response = try sendRequest(
                socketPath: fixture.paths.socketURL.path,
                request: JSONRPCClientRequest(
                    id: .number(bridgeRequest.id),
                    method: bridgeRequest.method,
                    params: bridgeRequest.params
                )
            )

            #expect(response.id == .number(bridgeRequest.id))
            #expect(response.error?.code == -32_003)
            #expect(response.error?.message == "unsupported target")
            #expect(response.result == nil)
        }
    }

    @Test("ungranted automation clients do not learn whether a pane is a Bridge pane")
    func ungrantedAutomationClientsDoNotLearnWhetherPaneIsBridgePane() throws {
        let paneId = UUID()
        let fixture = try LiveServerFixture(
            panes: [makePaneSummary(id: paneId, ordinal: 1, contentKind: .terminal)]
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()
        let principal = IPCPrincipal(
            principalId: UUID(),
            runtimeId: fixture.runtimeId,
            accessMode: .agentStudioOnly,
            kind: .automationClient,
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
        try login(connection: connection, token: token, requestId: 91, reader: &frameReader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(92),
                method: "bridge.diff.getPackage",
                params: .object(["handle": .string("pane:1")])
            )
        )

        let response = try frameReader.receiveResponse(connection: connection)
        #expect(response.error?.code == -32_002)
        #expect(response.error?.message == "unauthorized")
        #expect(response.result == nil)
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

    @Test("rejected Bridge page-control commands do not publish file selection notifications")
    func rejectedBridgePageControlCommandsDoNotPublishFileSelectionNotifications() throws {
        let paneId = UUID()
        let fixture = try LiveServerFixture(
            panes: [makePaneSummary(id: paneId, ordinal: 1, contentKind: .bridgePanel)],
            bridgePort: FakeBridgePort(
                paneId: paneId,
                pageControlStatus: "rejected",
                pageControlReason: "missing_item"
            )
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
        try login(connection: connection, token: token, requestId: 93, reader: &frameReader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(94),
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
                id: .number(95),
                method: "bridge.diff.scrollToFile",
                params: .object([
                    "handle": .string("pane:1"),
                    "itemId": .string("missing-item"),
                ])
            )
        )

        let response = try frameReader.receiveResponse(connection: connection)
        let result = try decodeResponseResult(IPCBridgePageControlResult.self, from: response)
        #expect(result.status == "rejected")
        #expect(result.reason == "missing_item")
        #expect(!frameReader.hasBufferedFrame(containing: "events.notification"))
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
