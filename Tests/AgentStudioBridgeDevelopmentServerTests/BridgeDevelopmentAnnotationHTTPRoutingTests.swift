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
        let restoredDraft = try await restoreHTTPAnnotationDraftAfterRestart(
            runtime: secondRuntime,
            draftBody: draftBody,
            sessionID: firstObservation.sessionID
        )
        try await secondRuntime.composition.shutdown()

        #expect(firstObservation.connection.bootstrap.paneSessionId == paneID.uuidString)
        #expect(restoredDraft.draft?.body == draftBody)
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
        try await executeHTTPAnnotationCommand(
            client: client,
            connection: connection,
            operation: [
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
            ],
            requestID: "annotation-create-before-restart",
            requestSequence: 5
        )
        let createOutcome: BridgeProductWorktreeAnnotationCommandOutcomeDTO =
            try await waitForHTTPAnnotationCommandOutcome(
                client: client,
                connection: connection,
                recorder: preparation.metadataStream.recorder,
                requestID: "annotation-create-before-restart"
            )
        guard case .committed = createOutcome.status,
            let sessionID = createOutcome.sessionId
        else { throw HTTPAnnotationIntegrationError.annotationCommandFailed }
        _ = try await waitForAcknowledgedDraft(
            client: client,
            connection: connection,
            recorder: preparation.metadataStream.recorder,
            body: draftBody,
            sessionID: sessionID
        )
        await runtime.host.shutdown()
        try await waitForHTTPMetadataStreamTermination(preparation.metadataStream.drain)
        return HTTPAnnotationDraftObservation(connection: connection, sessionID: sessionID)
    }
}

@MainActor
private func restoreHTTPAnnotationDraftAfterRestart(
    runtime: HTTPDevelopmentProductRuntime,
    draftBody: String,
    sessionID: UUID
) async throws -> BridgeProductWorktreeAnnotationMessageEntry {
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
        try await openHTTPSubscription(
            client: client,
            connection: connection,
            requestSequence: 2,
            subscription: ["subscriptionKind": "file.annotations"],
            subscriptionID: "file-annotations-second"
        )
        _ = try await waitForAcknowledgedSubscription(
            client: client,
            connection: connection,
            recorder: metadataStream.recorder,
            subscriptionID: "file-annotations-second"
        )
        try await executeHTTPAnnotationCommand(
            client: client,
            connection: connection,
            operation: ["kind": "session.discover"],
            requestID: "annotation-discover-after-restart",
            requestSequence: 3
        )
        let _: BridgeProductWorktreeAnnotationSessionSummary = try await waitForAcknowledgedMetadataFrame(
            client: client,
            connection: connection,
            recorder: metadataStream.recorder
        ) { frame -> BridgeProductWorktreeAnnotationSessionSummary? in
            guard case .subscriptionData(let dataFrame) = frame,
                case .fileAnnotations(.projectionState(let state)) = dataFrame.data
            else { return nil }
            return state.sessions.first(where: { $0.sessionId == sessionID })
        }
        try await executeHTTPAnnotationCommand(
            client: client,
            connection: connection,
            operation: [
                "kind": "demand.acquire",
                "sessionId": sessionID.uuidString.lowercased(),
            ],
            requestID: "annotation-demand-after-restart",
            requestSequence: 4
        )
        let restoredDraft = try await waitForAcknowledgedDraft(
            client: client,
            connection: connection,
            recorder: metadataStream.recorder,
            body: draftBody,
            sessionID: sessionID
        )
        await runtime.host.shutdown()
        try await waitForHTTPMetadataStreamTermination(metadataStream.drain)
        return restoredDraft
    }
}
