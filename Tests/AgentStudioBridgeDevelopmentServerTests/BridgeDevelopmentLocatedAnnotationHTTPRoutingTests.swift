import AgentStudioTestSupport
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing

@testable import AgentStudioBridge
@testable import AgentStudioBridgeDevelopmentServer
@testable import AgentStudioCore

@Suite("Bridge development located annotation HTTP routing")
struct BridgeDevelopmentLocatedAnnotationHTTPRoutingTests {
    @MainActor
    @Test("located saved annotation restores exact placement before File descriptor materialization")
    func locatedSavedAnnotationRestoresBeforeDescriptorMaterialization() async throws {
        // Arrange
        let repositoryURL = try FilesystemTestGitRepo.create(
            named: "bridge-development-http-located-annotation-restart"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repositoryURL)
        let paneID = PaneId.generateUUIDv7().uuid
        let dataRoot = FileManager.default.temporaryDirectory.appending(
            path: "bridge-development-http-located-annotation-data-\(paneID.uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: dataRoot) }

        let firstRuntime = try await makeHTTPDevelopmentProductRuntime(
            dataRoot: dataRoot,
            paneID: paneID,
            worktreeRoot: repositoryURL
        )
        let savedAnnotation = try await createHTTPSavedLocatedAnnotationBeforeRestart(
            runtime: firstRuntime
        )
        try await firstRuntime.composition.shutdown()

        let restartedRuntime = try await makeHTTPDevelopmentProductRuntime(
            dataRoot: dataRoot,
            paneID: paneID,
            worktreeRoot: repositoryURL
        )

        // Act
        let restoredBatch = try await restoreHTTPLocatedAnnotationBeforeDescriptorMaterialization(
            runtime: restartedRuntime,
            savedAnnotation: savedAnnotation
        )
        try await restartedRuntime.composition.shutdown()

        // Assert
        let restoredMessage = try #require(restoredBatch.messages.first?.message)
        #expect(restoredMessage.sessionId == savedAnnotation.sessionID)
        #expect(restoredBatch.messages.first?.context.threadId == savedAnnotation.threadID)
        #expect(restoredMessage.messageId == savedAnnotation.messageID)
        #expect(restoredMessage.savedRevision == savedAnnotation.savedRevision)
        #expect(restoredBatch.messages.first?.context.placement == .exact)
        #expect(restoredBatch.messages.first?.context.sourceIdentity == savedAnnotation.descriptorID)
    }
}

private struct HTTPSavedLocatedAnnotationObservation {
    let descriptorID: String
    let messageID: UUID
    let sessionID: UUID
    let threadID: UUID
    let savedRevision: Int
}

@MainActor
private func createHTTPSavedLocatedAnnotationBeforeRestart(
    runtime: HTTPDevelopmentProductRuntime
) async throws -> HTTPSavedLocatedAnnotationObservation {
    let application = BridgeDevelopmentHTTPApplication.make(host: runtime.host)
    return try await application.test(.router) { client in
        let connection = try await openHTTPProductConnection(client: client)
        let context = try await prepareHTTPAnnotationAuthoring(
            client: client,
            runtime: runtime,
            connection: connection
        )
        let createOutcome = try await executeHTTPAnnotationCommand(
            client: client,
            connection: connection,
            operation: [
                "admission": ["kind": "implicitOrSingle"],
                "body": "Saved located annotation",
                "editToken": "located-editor-1",
                "kind": "root.create",
                "origin": [
                    "diffSide": NSNull(),
                    "endLine": 2,
                    "kind": "located",
                    "path": "tracked.txt",
                    "sourceIdentity": context.descriptor.descriptorId,
                    "sourceRole": "file",
                    "startLine": 2,
                ],
            ],
            requestID: "annotation-create-located-before-restart",
            requestSequence: 6
        )
        guard case .committed = createOutcome.status,
            let sessionID = createOutcome.sessionId
        else { throw HTTPAnnotationIntegrationError.annotationCommandFailed }
        let createInvalidation = try await waitForHTTPAnnotationInvalidation(
            client: client,
            connection: connection,
            recorder: context.metadataStream.recorder
        )
        #expect(try httpAnnotationInvalidationIsCompact(createInvalidation))
        let draftProjection = try await fetchHTTPFileAnnotationProjection(
            client: client,
            host: runtime.host,
            connection: connection,
            demandedSessionIDs: [sessionID],
            sourceGeneration: context.fileSourceGeneration,
            requestSequence: 7
        )
        let draft = try #require(draftProjection.messages.first?.message)
        #expect(draft.draft?.body == "Saved located annotation")
        let saveOutcome = try await executeHTTPAnnotationCommand(
            client: client,
            connection: connection,
            operation: [
                "editToken": try #require(draft.draft?.activeEditToken),
                "expectedDraftRevision": try #require(draft.draft?.revision),
                "expectedSessionRevision": draft.sessionRevision,
                "kind": "draft.save",
                "messageId": draft.messageId.uuidString.lowercased(),
                "sessionId": sessionID.uuidString.lowercased(),
            ],
            requestID: "annotation-save-located-before-restart",
            requestSequence: 8
        )
        guard case .committed = saveOutcome.status else {
            throw HTTPAnnotationIntegrationError.annotationCommandFailed
        }
        let saveInvalidation = try await waitForHTTPAnnotationInvalidation(
            client: client,
            connection: connection,
            recorder: context.metadataStream.recorder
        )
        #expect(try httpAnnotationInvalidationIsCompact(saveInvalidation))
        let savedProjection = try await fetchHTTPFileAnnotationProjection(
            client: client,
            host: runtime.host,
            connection: connection,
            demandedSessionIDs: [sessionID],
            sourceGeneration: context.fileSourceGeneration,
            requestSequence: 9
        )
        let savedRecord = try #require(savedProjection.messages.first)
        let savedMessage = savedRecord.message
        #expect(savedRecord.context.threadId == draft.threadId)
        #expect(savedMessage.messageId == draft.messageId)
        #expect(savedMessage.savedBody == "Saved located annotation")
        #expect(savedMessage.draft == nil)
        try await shutdownHTTPHostAndDrainMetadataStream(
            host: runtime.host,
            drain: context.metadataStream.drain
        )
        return HTTPSavedLocatedAnnotationObservation(
            descriptorID: context.descriptor.descriptorId,
            messageID: savedMessage.messageId,
            sessionID: savedMessage.sessionId,
            threadID: savedMessage.threadId,
            savedRevision: try #require(savedMessage.savedRevision)
        )
    }
}

@MainActor
private func restoreHTTPLocatedAnnotationBeforeDescriptorMaterialization(
    runtime: HTTPDevelopmentProductRuntime,
    savedAnnotation: HTTPSavedLocatedAnnotationObservation
) async throws -> HTTPAnnotationProjectionSnapshot {
    let application = BridgeDevelopmentHTTPApplication.make(host: runtime.host)
    return try await application.test(.router) { client in
        let context = try await prepareHTTPAnnotationLocatedRestore(
            client: client,
            runtime: runtime
        )
        let initialProjection = try await fetchHTTPFileAnnotationProjection(
            client: client,
            host: runtime.host,
            connection: context.connection,
            demandedSessionIDs: [savedAnnotation.sessionID],
            sourceGeneration: context.fileSourceGeneration,
            requestSequence: 5
        )
        #expect(initialProjection.messages.first?.message.messageId == savedAnnotation.messageID)
        let refreshOutcome = try await executeHTTPAnnotationCommand(
            client: client,
            connection: context.connection,
            operation: [
                "kind": "source.refresh",
                "sessionId": savedAnnotation.sessionID.uuidString.lowercased(),
                "sourceEpoch": 1,
            ],
            requestID: "annotation-refresh-located-after-restart",
            requestSequence: 6
        )
        guard case .committed = refreshOutcome.status else {
            throw HTTPAnnotationIntegrationError.annotationCommandFailed
        }
        let refreshInvalidation = try await waitForHTTPAnnotationInvalidation(
            client: client,
            connection: context.connection,
            recorder: context.metadataStream.recorder
        )
        #expect(try httpAnnotationInvalidationIsCompact(refreshInvalidation))
        let refreshedProjection = try await fetchHTTPFileAnnotationProjection(
            client: client,
            host: runtime.host,
            connection: context.connection,
            demandedSessionIDs: [savedAnnotation.sessionID],
            sourceGeneration: context.fileSourceGeneration,
            requestSequence: 7
        )
        try await shutdownHTTPHostAndDrainMetadataStream(
            host: runtime.host,
            drain: context.metadataStream.drain
        )
        return refreshedProjection
    }
}
