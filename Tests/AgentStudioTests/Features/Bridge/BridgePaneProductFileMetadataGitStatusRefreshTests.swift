import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioBridge

extension BridgePaneProductFileMetadataSourceTests {
    @Test("Git-internal changes refresh status instead of stranding stale status")
    func gitInternalChangesRefreshStatusInsteadOfStrandingStaleStatus() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let source = fixture.makeSource()
        try await source.open(
            subscription: fixture.openSnapshot(),
            productAdmission: fixture.productAdmission.context
        ) { _ in }

        // Act
        let emissions = try await source.publish(
            changeset: FileChangeset(
                worktreeId: fixture.worktreeId,
                repoId: fixture.repoId,
                rootPath: fixture.rootURL,
                paths: [".git/refs/heads/main"],
                containsGitInternalChanges: true,
                timestamp: .now,
                batchSeq: 1
            ),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: refreshWorkAdmission.admission
        )

        // Assert
        let statusPatches = emissions.compactMap { emission -> BridgeProductFileStatusPatch? in
            guard case .statusPatch(let event) = emission.event else { return nil }
            return event.patch
        }
        #expect(statusPatches.count == 1)
        let statusPatch = try #require(statusPatches.first)
        guard case .summary(let summary) = statusPatch else {
            Issue.record("Expected refreshed status summary after a Git-internal change")
            return
        }
        #expect(summary.branchName == "main")
        #expect(summary.staged == 2)
        #expect(summary.unstaged == 1)
        #expect(summary.untracked == 3)
    }
}
