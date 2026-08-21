import AgentStudioTestSupport
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing

@testable import AgentStudioBridge
@testable import AgentStudioBridgeDevelopmentServer
@testable import AgentStudioCore

@Suite("Bridge development annotation HTTP routing")
struct BridgeDevelopmentAnnotationHTTPRoutingTests {
    @MainActor
    @Test("successful annotation output returns its completed HTTP result")
    func successfulAnnotationOutputReturnsCompletedHTTPResult() async throws {
        // Arrange
        let repositoryURL = try FilesystemTestGitRepo.create(
            named: "bridge-development-http-annotation-output-result"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repositoryURL)
        let paneID = PaneId.generateUUIDv7().uuid
        let dataRoot = FileManager.default.temporaryDirectory.appending(
            path: "bridge-development-http-annotation-output-result-\(paneID.uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        let runtime = try await makeHTTPDevelopmentProductRuntime(
            dataRoot: dataRoot,
            paneID: paneID,
            worktreeRoot: repositoryURL
        )
        let application = BridgeDevelopmentHTTPApplication.make(host: runtime.host)

        try await application.test(.router) { client in
            let connection = try await openHTTPProductConnection(client: client)
            let preparation = try await prepareHTTPAnnotationAuthoring(
                client: client,
                runtime: runtime,
                connection: connection
            )
            let createOutcome = try await executeHTTPAnnotationCommand(
                client: client,
                connection: connection,
                operation: twoPaneRootCreateOperation(
                    sourceIdentity: preparation.descriptor.descriptorId
                ),
                requestID: "annotation-output-result-create",
                requestSequence: 6
            )
            let createReceipt = try #require(createOutcome.receipt)
            let sessionID = try #require(createOutcome.sessionId)
            _ = try await waitForHTTPAnnotationInvalidation(
                client: client,
                connection: connection,
                recorder: preparation.metadataStream.recorder
            )
            let saveOutcome = try await executeHTTPAnnotationCommand(
                client: client,
                connection: connection,
                operation: [
                    "editToken": "two-pane-editor",
                    "expectedDraftRevision": try #require(createReceipt.draftRevision),
                    "expectedSessionRevision": createReceipt.sessionRevision,
                    "kind": "draft.save",
                    "messageId": createReceipt.messageId.uuidString.lowercased(),
                    "sessionId": sessionID.uuidString.lowercased(),
                ],
                requestID: "annotation-output-result-save",
                requestSequence: 7
            )
            #expect(saveOutcome.status == .committed)
            _ = try await waitForHTTPAnnotationInvalidation(
                client: client,
                connection: connection,
                recorder: preparation.metadataStream.recorder
            )
            let projection = try await fetchHTTPFileAnnotationProjection(
                client: client,
                host: runtime.host,
                connection: connection,
                demandedSessionIDs: [sessionID],
                sourceGeneration: preparation.fileSourceGeneration,
                requestSequence: 8
            )
            let savedMessage = try #require(projection.messages.first?.message)

            // Act
            let outputOutcome = try await executeHTTPAnnotationCommand(
                client: client,
                connection: connection,
                operation: [
                    "displayedProjectionRevision": projection.header.projectionRevision,
                    "expectedSessionRevision": savedMessage.sessionRevision,
                    "kind": "output.scope.commit",
                    "outputKind": "clipboardMarkdown",
                    "scope": "all",
                    "sessionId": sessionID.uuidString.lowercased(),
                    "sourceGeneration": preparation.fileSourceGeneration,
                ],
                requestID: "annotation-output-result-copy",
                requestSequence: 9
            )

            // Assert
            guard case .output(.succeeded(let summary)) = outputOutcome.status else {
                Issue.record("Expected the successful output result to cross the HTTP response")
                return
            }
            #expect(summary.sessionId == sessionID)
            #expect(summary.outputKind == .clipboardMarkdown)
            #expect(summary.messageCount == 1)
            try await shutdownHTTPHostAndDrainMetadataStream(
                host: runtime.host,
                drain: preparation.metadataStream.drain
            )
        }
        try await runtime.composition.shutdown()
    }

    @MainActor
    @Test("annotation mutation converges through independent pane projections")
    func annotationMutationConvergesThroughIndependentPaneProjections() async throws {
        let repositoryURL = try FilesystemTestGitRepo.create(
            named: "bridge-development-http-annotation-two-pane"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repositoryURL)
        let paneAID = PaneId.generateUUIDv7().uuid
        let paneBID = PaneId.generateUUIDv7().uuid
        let dataRoot = FileManager.default.temporaryDirectory.appending(
            path: "bridge-development-http-annotation-two-pane-\(paneAID.uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        let paneA = try await makeHTTPDevelopmentProductRuntime(
            dataRoot: dataRoot,
            paneID: paneAID,
            worktreeRoot: repositoryURL
        )
        let paneB = try await makeSiblingHTTPDevelopmentProductRuntime(
            composition: paneA.composition,
            paneID: paneBID
        )
        let applicationA = BridgeDevelopmentHTTPApplication.make(host: paneA.host)
        let applicationB = BridgeDevelopmentHTTPApplication.make(host: paneB.host)

        try await applicationA.test(.router) { clientA in
            try await applicationB.test(.router) { clientB in
                let connectionA = try await openHTTPProductConnection(client: clientA)
                let connectionB = try await openHTTPProductConnection(client: clientB)
                let preparationA = try await prepareHTTPAnnotationAuthoring(
                    client: clientA,
                    runtime: paneA,
                    connection: connectionA
                )
                let preparationB = try await prepareHTTPAnnotationAuthoring(
                    client: clientB,
                    runtime: paneB,
                    connection: connectionB
                )
                let outcome = try await executeHTTPAnnotationCommand(
                    client: clientA,
                    connection: connectionA,
                    operation: twoPaneRootCreateOperation(
                        sourceIdentity: preparationA.descriptor.descriptorId
                    ),
                    requestID: "annotation-create-two-pane",
                    requestSequence: 6
                )
                guard case .committed = outcome.status,
                    let sessionID = outcome.sessionId
                else { throw HTTPAnnotationIntegrationError.annotationCommandFailed }
                let invalidationA = try await waitForHTTPAnnotationInvalidation(
                    client: clientA,
                    connection: connectionA,
                    recorder: preparationA.metadataStream.recorder
                )
                let invalidationB = try await waitForHTTPAnnotationInvalidation(
                    client: clientB,
                    connection: connectionB,
                    recorder: preparationB.metadataStream.recorder
                )
                let projectionA = try await fetchHTTPFileAnnotationProjection(
                    client: clientA,
                    host: paneA.host,
                    connection: connectionA,
                    demandedSessionIDs: [sessionID],
                    sourceGeneration: preparationA.fileSourceGeneration,
                    requestSequence: 7
                )
                let projectionB = try await fetchHTTPFileAnnotationProjection(
                    client: clientB,
                    host: paneB.host,
                    connection: connectionB,
                    demandedSessionIDs: [sessionID],
                    sourceGeneration: preparationB.fileSourceGeneration,
                    requestSequence: 6
                )

                #expect(try httpAnnotationInvalidationIsCompact(invalidationA))
                #expect(try httpAnnotationInvalidationIsCompact(invalidationB))
                #expect(projectionA.header.projectionRevision == projectionB.header.projectionRevision)
                #expect(projectionA.header.sessions == projectionB.header.sessions)
                #expect(projectionA.messages == projectionB.messages)
                #expect(projectionB.messages.first?.message.draft?.body == "Visible from both panes")

                try await shutdownHTTPHostAndDrainMetadataStream(
                    host: paneA.host,
                    drain: preparationA.metadataStream.drain
                )
                try await shutdownHTTPHostAndDrainMetadataStream(
                    host: paneB.host,
                    drain: preparationB.metadataStream.drain
                )
            }
        }
        try await paneA.composition.shutdown()
    }

    @MainActor
    @Test("annotation draft survives a development host restart through the product HTTP carrier")
    func annotationDraftSurvivesDevelopmentHostRestart() async throws {
        let repositoryURL = try FilesystemTestGitRepo.create(
            named: "bridge-development-http-annotation-restart"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repositoryURL)
        let paneID = PaneId.generateUUIDv7().uuid
        let dataRoot = FileManager.default.temporaryDirectory.appending(
            path: "bridge-development-http-annotation-data-\(paneID.uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        let draftBody = "Draft restored from local.sqlite"

        let firstRuntime = try await makeHTTPDevelopmentProductRuntime(
            dataRoot: dataRoot,
            paneID: paneID,
            worktreeRoot: repositoryURL
        )
        let firstObservation = try await createHTTPAnnotationDraftBeforeRestart(
            runtime: firstRuntime,
            draftBody: draftBody
        )
        try await firstRuntime.composition.shutdown()

        let secondRuntime = try await makeHTTPDevelopmentProductRuntime(
            dataRoot: dataRoot,
            paneID: paneID,
            worktreeRoot: repositoryURL
        )
        let restoredProjection = try await restoreHTTPAnnotationDraftAfterRestart(
            runtime: secondRuntime,
            draftBody: draftBody,
            sessionID: firstObservation.sessionID
        )
        try await secondRuntime.composition.shutdown()

        #expect(firstObservation.connection.bootstrap.paneSessionId == paneID.uuidString)
        let restoredDraft = try #require(restoredProjection.messages.first?.message)
        #expect(restoredProjection.header.sessions.map(\.sessionId) == [firstObservation.sessionID])
        #expect(restoredDraft.draft?.body == draftBody)
        #expect(restoredDraft.savedBody == nil)
        #expect(restoredDraft.sessionId == firstObservation.sessionID)
    }

    @Test("metadata frame decode failure wakes a suspended recorder reader")
    func metadataFrameDecodeFailureWakesSuspendedRecorderReader() async throws {
        let recorder = try HTTPMetadataFrameRecorder()
        let pendingFrame = Task {
            try await recorder.nextFrame()
        }
        await recorder.waitUntilNextFrameSuspends()

        let writerError = await capturedErrorDescription {
            try await recorder.write(ByteBuffer(bytes: [0, 0, 0, 1, 0xFF]))
        }
        let readerError = await capturedErrorDescription {
            _ = try await pendingFrame.value
        }

        #expect(writerError != nil)
        #expect(readerError == writerError)
    }
}

private func twoPaneRootCreateOperation(sourceIdentity: String) -> [String: Any] {
    [
        "admission": ["kind": "implicitOrSingle"],
        "body": "Visible from both panes",
        "editToken": "two-pane-editor",
        "kind": "root.create",
        "origin": [
            "diffSide": NSNull(),
            "endLine": 2,
            "kind": "located",
            "path": "tracked.txt",
            "sourceIdentity": sourceIdentity,
            "sourceRole": "file",
            "startLine": 2,
        ],
    ]
}

@MainActor
private func makeSiblingHTTPDevelopmentProductRuntime(
    composition: BridgeDevelopmentServerCoreComposition,
    paneID: UUID
) async throws -> HTTPDevelopmentProductRuntime {
    let source = BridgeDevelopmentProductSource(
        paneID: paneID,
        paneState: composition.productSource.paneState,
        repoID: composition.productSource.repoID,
        reviewedSubjectLabel: composition.productSource.reviewedSubjectLabel,
        worktreeID: composition.productSource.worktreeID,
        worktreeRoot: composition.productSource.worktreeRoot
    )
    return try await HTTPDevelopmentProductRuntime(
        composition: composition,
        host: BridgeDevelopmentProductHost(
            source: source,
            worktreeAnnotationStore: composition.worktreeAnnotationStore,
            worktreeAnnotationOutputCoordinator: composition.worktreeAnnotationOutputCoordinator,
            originatingWorkspaceID: composition.originatingWorkspaceID,
            contributionTargetCommit: { target in
                composition.applyContributionTarget(target)
            }
        )
    )
}

@MainActor
private struct HTTPAnnotationDraftObservation {
    let connection: HTTPProductConnection
    let sessionID: UUID
}

@MainActor
private func createHTTPAnnotationDraftBeforeRestart(
    runtime: HTTPDevelopmentProductRuntime,
    draftBody: String
) async throws -> HTTPAnnotationDraftObservation {
    let application = BridgeDevelopmentHTTPApplication.make(host: runtime.host)
    return try await application.test(.router) { client in
        let connection = try await openHTTPProductConnection(client: client)
        let preparation = try await prepareHTTPAnnotationAuthoring(
            client: client,
            runtime: runtime,
            connection: connection
        )
        let createOperation: [String: Any] = [
            "admission": ["kind": "implicitOrSingle"],
            "body": draftBody,
            "editToken": "restart-editor-1",
            "kind": "root.create",
            "origin": [
                "diffSide": NSNull(),
                "endLine": 2,
                "kind": "located",
                "path": "tracked.txt",
                "sourceIdentity": preparation.descriptor.descriptorId,
                "sourceRole": "file",
                "startLine": 2,
            ],
        ]
        let createOutcome = try await executeHTTPAnnotationCommand(
            client: client,
            connection: connection,
            operation: createOperation,
            requestID: "annotation-create-before-restart",
            requestSequence: 6
        )
        guard case .committed = createOutcome.status,
            let sessionID = createOutcome.sessionId
        else { throw HTTPAnnotationIntegrationError.annotationCommandFailed }
        let invalidation = try await waitForHTTPAnnotationInvalidation(
            client: client,
            connection: connection,
            recorder: preparation.metadataStream.recorder
        )
        #expect(try httpAnnotationInvalidationIsCompact(invalidation))
        let projection = try await fetchHTTPFileAnnotationProjection(
            client: client,
            host: runtime.host,
            connection: connection,
            demandedSessionIDs: [sessionID],
            sourceGeneration: preparation.fileSourceGeneration,
            requestSequence: 7
        )
        let createdMessage = try #require(projection.messages.first?.message)
        #expect(createdMessage.draft?.body == draftBody)
        #expect(createdMessage.savedBody == nil)
        try await shutdownHTTPHostAndDrainMetadataStream(
            host: runtime.host,
            drain: preparation.metadataStream.drain
        )
        return HTTPAnnotationDraftObservation(connection: connection, sessionID: sessionID)
    }
}

@MainActor
private func restoreHTTPAnnotationDraftAfterRestart(
    runtime: HTTPDevelopmentProductRuntime,
    draftBody: String,
    sessionID: UUID
) async throws -> HTTPAnnotationProjectionSnapshot {
    let application = BridgeDevelopmentHTTPApplication.make(host: runtime.host)
    return try await application.test(.router) { client in
        let connection = try await openHTTPProductConnection(client: client)
        let metadataStream = try await startHTTPMetadataStream(
            host: runtime.host,
            connection: connection,
            streamID: "metadata-stream-annotation-second"
        )
        let _: BridgeProductMetadataStreamAcceptedFrame = try await waitForAcknowledgedMetadataFrame(
            client: client,
            connection: connection,
            recorder: metadataStream.recorder
        ) { frame -> BridgeProductMetadataStreamAcceptedFrame? in
            guard case .metadataStreamAccepted(let accepted) = frame else { return nil }
            return accepted
        }
        let fileSource = try await queryHTTPFileSource(
            client: client,
            connection: connection,
            requestSequence: 2,
        )
        _ = try await openHTTPSubscription(
            client: client,
            connection: connection,
            requestSequence: 3,
            subscription: [
                "source": try jsonObject(fileSource),
                "subscriptionKind": "file.metadata",
            ],
            subscriptionID: "file-metadata-annotation-second"
        )
        _ = try await waitForAcknowledgedSubscription(
            client: client,
            connection: connection,
            recorder: metadataStream.recorder,
            subscriptionID: "file-metadata-annotation-second"
        )
        let acceptedFileSource: BridgeProductFileSourceIdentity =
            try await waitForAcknowledgedMetadataFrame(
                client: client,
                connection: connection,
                recorder: metadataStream.recorder
            ) { frame in
                guard case .subscriptionData(let dataFrame) = frame,
                    case .fileMetadata(.sourceAccepted(let event)) = dataFrame.data
                else { return nil }
                return event.source
            }
        _ = try await openHTTPSubscription(
            client: client,
            connection: connection,
            requestSequence: 4,
            subscription: ["subscriptionKind": "file.annotations"],
            subscriptionID: "file-annotations-second"
        )
        _ = try await waitForAcknowledgedSubscription(
            client: client,
            connection: connection,
            recorder: metadataStream.recorder,
            subscriptionID: "file-annotations-second"
        )
        let initialInvalidation = try await waitForHTTPAnnotationInvalidation(
            client: client,
            connection: connection,
            recorder: metadataStream.recorder
        )
        #expect(try httpAnnotationInvalidationIsCompact(initialInvalidation))
        let restoredProjection = try await fetchHTTPFileAnnotationProjection(
            client: client,
            host: runtime.host,
            connection: connection,
            demandedSessionIDs: [sessionID],
            sourceGeneration: acceptedFileSource.subscriptionGeneration,
            requestSequence: 5
        )
        #expect(restoredProjection.messages.first?.message.draft?.body == draftBody)
        try await shutdownHTTPHostAndDrainMetadataStream(
            host: runtime.host,
            drain: metadataStream.drain
        )
        return restoredProjection
    }
}
