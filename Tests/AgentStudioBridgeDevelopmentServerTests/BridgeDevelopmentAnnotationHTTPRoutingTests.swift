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
