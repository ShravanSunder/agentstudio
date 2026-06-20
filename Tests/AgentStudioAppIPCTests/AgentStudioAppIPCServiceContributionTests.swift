import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

@Suite("AgentStudio App IPC service contributed methods", .serialized)
struct AgentStudioAppIPCServiceContributionTests {
    @Test("server advertises contributed pane snapshot in system capabilities")
    func serverAdvertisesContributedPaneSnapshotInSystemCapabilities() throws {
        let fixture = try LiveServerFixture(
            methodContributions: try AgentStudioIPCContributionRegistry.phaseAComposition().methodContributions
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()
        let principal = IPCPrincipal(
            principalId: UUID(),
            runtimeId: fixture.runtimeId,
            accessMode: .agentStudioOnly,
            kind: .spawnedPaneAgent(boundPaneId: fixture.boundPaneId.uuidString, boundWorkspaceId: nil),
            approvalAuthority: .noApprovalAuthority
        )
        let token = try fixture.server.principalRegistry.issueSubjectToken(for: principal)
        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        defer {
            connection.close()
        }
        var reader = TestFrameReader()
        try login(connection: connection, token: token, requestId: 78, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(79),
                method: "system.capabilities",
                params: .object([:])
            )
        )
        let response = try reader.receiveResponse(connection: connection)

        #expect(response.error == nil)
        let result = try decodeResponseResult(IPCSystemCapabilitiesResult.self, from: response)
        let paneSnapshot = result.methods.first { $0.name == "pane.snapshot" }
        #expect(paneSnapshot != nil)
        #expect(paneSnapshot?.privilegeClasses == [.paneContextRead])
        #expect(paneSnapshot?.executionOwner == .queryReader)
        #expect(paneSnapshot?.resultSemantics == .applied)
    }

    @Test("server rejects contributed methods that authorize targets outside their contract")
    func serverRejectsContributedMethodsThatAuthorizeTargetsOutsideTheirContract() throws {
        let contribution = try AppIPCMethodContribution(
            definition: IPCMethodDefinition(
                name: "pane.badTarget",
                paramsSchema: IPCSchemaDescription(name: "pane.badTarget.params"),
                resultSchema: IPCSchemaDescription(name: "pane.badTarget.result"),
                privilegeClasses: [.paneContextRead],
                principalAvailability: .authenticated,
                executionOwner: .queryReader,
                resultSemantics: .applied
            ),
            securityContract: AppIPCContributionSecurityContract(
                targetVocabulary: [.pane],
                dataScopes: [.paneContext],
                sensitiveDataExclusions: ["cwd"]
            ),
            authorizationContext: { request, _, _ in
                AppIPCAuthorizedRequestContext(request: request, target: .app)
            },
            dispatch: { _, _, _ in
                .object(["unexpected": .bool(true)])
            }
        )
        let fixture = try LiveServerFixture(methodContributions: [contribution])
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()
        let principal = IPCPrincipal(
            principalId: UUID(),
            runtimeId: fixture.runtimeId,
            accessMode: .agentStudioOnly,
            kind: .spawnedPaneAgent(boundPaneId: fixture.boundPaneId.uuidString, boundWorkspaceId: nil),
            approvalAuthority: .noApprovalAuthority
        )
        let token = try fixture.server.principalRegistry.issueSubjectToken(for: principal)
        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        defer {
            connection.close()
        }
        var reader = TestFrameReader()
        try login(connection: connection, token: token, requestId: 88, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(89),
                method: "pane.badTarget",
                params: .object([:])
            )
        )
        let response = try reader.receiveResponse(connection: connection)

        #expect(response.error?.code == -32_002)
        #expect(response.error?.message == "unauthorized")
    }

    @Test("server rejects contributed dispatch reading a pane outside the authorized target")
    func serverRejectsContributedDispatchReadingPaneOutsideAuthorizedTarget() throws {
        let allowedPaneId = UUID()
        let forbiddenPaneId = UUID()
        let queryPort = RecordingSnapshotQueryPort(
            runtimeId: UUID(),
            panes: [
                makePaneSummary(id: allowedPaneId, ordinal: 1),
                makePaneSummary(id: forbiddenPaneId, ordinal: 2),
            ]
        )
        let contribution = try maliciousPaneSnapshotContribution(authorizedPaneId: allowedPaneId)
        let fixture = try LiveServerFixture(
            panes: queryPort.panes,
            queryPort: queryPort,
            methodContributions: [contribution]
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()
        let principal = IPCPrincipal(
            principalId: UUID(),
            runtimeId: fixture.runtimeId,
            accessMode: .agentStudioOnly,
            kind: .spawnedPaneAgent(boundPaneId: allowedPaneId.uuidString, boundWorkspaceId: nil),
            approvalAuthority: .noApprovalAuthority
        )
        let token = try fixture.server.principalRegistry.issueSubjectToken(for: principal)
        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        defer {
            connection.close()
        }
        var reader = TestFrameReader()
        try login(connection: connection, token: token, requestId: 90, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(91),
                method: "pane.maliciousSnapshot",
                params: .object(["handle": .string("pane:\(forbiddenPaneId.uuidString)")])
            )
        )
        let response = try reader.receiveResponse(connection: connection)

        #expect(response.error?.code == -32_002)
        #expect(response.error?.message == "unauthorized")
        #expect(queryPort.snapshotPaneIds.isEmpty)
    }

    @Test("server dispatches contributed pane snapshot after friendly handle canonicalization")
    func serverDispatchesContributedPaneSnapshotAfterFriendlyHandleCanonicalization() throws {
        let paneId = UUID()
        let queryPort = RecordingSnapshotQueryPort(
            runtimeId: UUID(),
            panes: [makePaneSummary(id: paneId, ordinal: 1)]
        )
        let fixture = try LiveServerFixture(
            panes: [makePaneSummary(id: paneId, ordinal: 1)],
            queryPort: queryPort,
            methodContributions: try AgentStudioIPCContributionRegistry.phaseAComposition().methodContributions
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
        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        defer {
            connection.close()
        }
        var reader = TestFrameReader()
        try login(connection: connection, token: token, requestId: 80, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(81),
                method: "pane.snapshot",
                params: .object(["handle": .string("pane:1")])
            )
        )
        let response = try reader.receiveResponse(connection: connection)

        #expect(response.error == nil)
        let result = try decodeResponseResult(IPCPaneSnapshotResult.self, from: response)
        #expect(result.pane.id == paneId)
        #expect(queryPort.snapshotPaneIds == [paneId])
    }

    @Test("server denies contributed pane snapshot before handler invocation")
    func serverDeniesContributedPaneSnapshotBeforeHandlerInvocation() throws {
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let queryPort = RecordingSnapshotQueryPort(
            runtimeId: UUID(),
            panes: [
                makePaneSummary(id: firstPaneId, ordinal: 1),
                makePaneSummary(id: secondPaneId, ordinal: 2),
            ]
        )
        let fixture = try LiveServerFixture(
            panes: queryPort.panes,
            queryPort: queryPort,
            methodContributions: try AgentStudioIPCContributionRegistry.phaseAComposition().methodContributions
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()
        let principal = IPCPrincipal(
            principalId: UUID(),
            runtimeId: fixture.runtimeId,
            accessMode: .agentStudioOnly,
            kind: .spawnedPaneAgent(boundPaneId: secondPaneId.uuidString, boundWorkspaceId: nil),
            approvalAuthority: .noApprovalAuthority
        )
        let token = try fixture.server.principalRegistry.issueSubjectToken(for: principal)
        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        defer {
            connection.close()
        }
        var reader = TestFrameReader()
        try login(connection: connection, token: token, requestId: 82, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(83),
                method: "pane.snapshot",
                params: .object(["handle": .string("pane:1")])
            )
        )
        let response = try reader.receiveResponse(connection: connection)

        #expect(response.error?.code == -32_002)
        #expect(response.error?.message == "unauthorized")
        #expect(queryPort.snapshotPaneIds.isEmpty)
    }

    @Test("server rejects malformed contributed pane snapshot params as invalid params")
    func serverRejectsMalformedContributedPaneSnapshotParamsAsInvalidParams() throws {
        let paneId = UUID()
        let queryPort = RecordingSnapshotQueryPort(
            runtimeId: UUID(),
            panes: [makePaneSummary(id: paneId, ordinal: 1)]
        )
        let fixture = try LiveServerFixture(
            panes: queryPort.panes,
            queryPort: queryPort,
            methodContributions: try AgentStudioIPCContributionRegistry.phaseAComposition().methodContributions
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
        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        defer {
            connection.close()
        }
        var reader = TestFrameReader()
        try login(connection: connection, token: token, requestId: 84, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(85),
                method: "pane.snapshot",
                params: .object([:])
            )
        )
        let response = try reader.receiveResponse(connection: connection)

        #expect(response.error?.code == -32_602)
        #expect(response.error?.message == "invalid params")
        #expect(queryPort.snapshotPaneIds.isEmpty)
    }

    @Test("server rejects wrong-kind contributed pane snapshot handles before dispatch")
    func serverRejectsWrongKindContributedPaneSnapshotHandlesBeforeDispatch() throws {
        let paneId = UUID()
        let workspaceId = UUID()
        let queryPort = RecordingSnapshotQueryPort(
            runtimeId: UUID(),
            panes: [makePaneSummary(id: paneId, ordinal: 1)]
        )
        let fixture = try LiveServerFixture(
            panes: queryPort.panes,
            queryPort: queryPort,
            methodContributions: try AgentStudioIPCContributionRegistry.phaseAComposition().methodContributions
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
        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        defer {
            connection.close()
        }
        var reader = TestFrameReader()
        try login(connection: connection, token: token, requestId: 86, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(87),
                method: "pane.snapshot",
                params: .object(["handle": .string("workspace:\(workspaceId.uuidString)")])
            )
        )
        let response = try reader.receiveResponse(connection: connection)

        #expect(response.error?.code == -32_004)
        #expect(response.error?.message == "target not found")
        #expect(queryPort.snapshotPaneIds.isEmpty)
    }

    @Test("server rejects contributed pane snapshot before login")
    func serverRejectsContributedPaneSnapshotBeforeLogin() throws {
        let paneId = UUID()
        let queryPort = RecordingSnapshotQueryPort(
            runtimeId: UUID(),
            panes: [makePaneSummary(id: paneId, ordinal: 1)]
        )
        let fixture = try LiveServerFixture(
            panes: [makePaneSummary(id: paneId, ordinal: 1)],
            queryPort: queryPort,
            methodContributions: try AgentStudioIPCContributionRegistry.phaseAComposition().methodContributions
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        let response = try sendRequest(
            socketPath: fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(84),
                method: "pane.snapshot",
                params: .object(["handle": .string("pane:1")])
            )
        )

        #expect(response.error?.code == -32_001)
        #expect(response.error?.message == "unauthenticated")
        #expect(queryPort.snapshotPaneIds.isEmpty)
    }
}

private func maliciousPaneSnapshotContribution(authorizedPaneId: UUID) throws -> AppIPCMethodContribution {
    try AppIPCMethodContribution(
        definition: IPCMethodDefinition(
            name: "pane.maliciousSnapshot",
            paramsSchema: IPCSchemaDescription(name: "pane.maliciousSnapshot.params"),
            resultSchema: IPCSchemaDescription(name: "pane.maliciousSnapshot.result"),
            privilegeClasses: [.paneContextRead],
            executionOwner: .queryReader,
            resultSemantics: .applied
        ),
        securityContract: AppIPCContributionSecurityContract(
            targetVocabulary: [.pane],
            dataScopes: [.paneContext],
            sensitiveDataExclusions: ["cwd"]
        ),
        authorizationContext: { request, _, _ in
            AppIPCAuthorizedRequestContext(request: request, target: .pane(authorizedPaneId.uuidString))
        },
        dispatch: { request, _, context in
            let params = try AppIPCContributionParameters.decode(ContributionHandleParams.self, from: request.params)
            let paneId = try context.uuidFromPaneHandle(params.handle)
            let snapshot = try await context.snapshotPane(paneId)
            return try JSONRPCCodec.encodeJSONValue(snapshot)
        }
    )
}
