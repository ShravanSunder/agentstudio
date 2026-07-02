import Foundation
import Testing
import WebKit

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeWorktreeFileInterestTransportTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("metadata interest serves accepted generation manifest without filesystem rewalk")
        func metadataInterestServesAcceptedGenerationManifestWithoutFilesystemRewalk() async throws {
            let fixture = try makeControllerFixture()
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let initialFileURL = fixture.rootURL.appending(path: "Initial.swift")
            try "let initial = true\n".write(to: initialFileURL, atomically: true, encoding: .utf8)
            let outcome = try await fixture.controller.handleWorktreeFileSurfaceOpenSourceStream(
                sourceSpec(
                    fixture: fixture,
                    clientRequestId: "request-generation-manifest-index",
                    pathScope: []
                )
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            let queuedJobsBeforeInterest = await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount

            let lateFileURL = fixture.rootURL.appending(path: "LateAfterOpen.swift")
            try "let late = true\n".write(to: lateFileURL, atomically: true, encoding: .utf8)

            try await fixture.controller.handleWorktreeFileMetadataInterestUpdate(
                ReviewMethods.MetadataInterestUpdateMethod.Params(
                    protocolId: "worktree-file",
                    streamId: outcome.streamId,
                    generation: outcome.generation,
                    itemIds: nil,
                    paths: ["LateAfterOpen.swift"],
                    lane: .foreground,
                    loadedBy: nil
                )
            )

            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == queuedJobsBeforeInterest)

            fixture.controller.teardown()
        }
    }
}
