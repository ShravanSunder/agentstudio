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
        let restoredMessage = try #require(restoredBatch.messages.first)
        #expect(restoredMessage.sessionId == savedAnnotation.sessionID)
        #expect(restoredBatch.context.threadId == savedAnnotation.threadID)
        #expect(restoredMessage.messageId == savedAnnotation.messageID)
        #expect(restoredMessage.savedRevision == savedAnnotation.savedRevision)
        #expect(restoredBatch.context.placement == .exact)
        #expect(restoredBatch.context.sourceIdentity == savedAnnotation.descriptorID)
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
        try await executeHTTPAnnotationCommand(
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
        let createOutcome = try await waitForHTTPAnnotationCommandOutcome(
            client: client,
            connection: connection,
            recorder: context.metadataStream.recorder,
            requestID: "annotation-create-located-before-restart"
        )
        guard case .committed = createOutcome.status,
            let sessionID = createOutcome.sessionId
        else { throw HTTPAnnotationIntegrationError.annotationCommandFailed }
        let draftBatch = try await waitForHTTPAnnotationMessageBatch(
            client: client,
            connection: connection,
            recorder: context.metadataStream.recorder
        ) { batch in
            batch.messages.contains(where: {
                $0.sessionId == sessionID && $0.draft?.body == "Saved located annotation"
            })
        }
        let draft = try #require(draftBatch.messages.first(where: { $0.sessionId == sessionID }))
        try await executeHTTPAnnotationCommand(
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
            requestSequence: 7
        )
        let savedBatch = try await waitForHTTPAnnotationMessageBatch(
            client: client,
            connection: connection,
            recorder: context.metadataStream.recorder
        ) { batch in
            batch.context.threadId == draft.threadId
                && batch.messages.contains(where: {
                    $0.messageId == draft.messageId && $0.savedRevision != nil
                })
        }
        let savedMessage = try #require(
            savedBatch.messages.first(where: {
                $0.messageId == draft.messageId
            }))
        await runtime.host.shutdown()
        try await waitForHTTPMetadataStreamTermination(context.metadataStream.drain)
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
) async throws -> BridgeProductWorktreeAnnotationMessageBatch {
    let application = BridgeDevelopmentHTTPApplication.make(host: runtime.host)
    return try await application.test(.router) { client in
        let context = try await prepareHTTPAnnotationLocatedRestore(
            client: client,
            runtime: runtime,
            sessionID: savedAnnotation.sessionID,
            threadID: savedAnnotation.threadID,
            messageID: savedAnnotation.messageID
        )
        try await executeHTTPAnnotationCommand(
            client: client,
            connection: context.connection,
            operation: [
                "kind": "source.refresh",
                "sessionId": savedAnnotation.sessionID.uuidString.lowercased(),
                "sourceEpoch": 1,
            ],
            requestID: "annotation-refresh-located-after-restart",
            requestSequence: 7
        )
        let refreshedBatch = try await waitForHTTPAnnotationMessageBatch(
            client: client,
            connection: context.connection,
            recorder: context.metadataStream.recorder
        ) { batch in
            batch.context.threadId == savedAnnotation.threadID
                && batch.messages.contains(where: { $0.messageId == savedAnnotation.messageID })
        }
        await runtime.host.shutdown()
        try await waitForHTTPMetadataStreamTermination(context.metadataStream.drain)
        return refreshedBatch
    }
}
