import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

extension WebKitSerializedTests.BridgePaneControllerTests {
    @Test("refresh follows explicit bindings: a Files-only member refreshes Files, never Review")
    func refreshFollowsExplicitSourceBindings() async throws {
        // Arrange
        let filesOnlyMember = Worktree(
            id: UUIDv7.generate(),
            repoId: UUIDv7.generate(),
            name: "files-only-member",
            path: URL(fileURLWithPath: "/tmp/bridge-refresh-files-only-member")
        )
        let fixture = try await makeRefreshAdmissionIntegrationFixture(additionalFilesMember: filesOnlyMember)
        try await fixture.loadInitialReviewPackage()
        // fire-and-forget: the test asserts admission state; the presentation transition handle is not its claim
        _ = fixture.controller.applyBridgePaneActivity(.loadedHidden)
        let unrelatedChangeset = FileChangeset(
            worktreeId: UUIDv7.generate(),
            repoId: UUIDv7.generate(),
            rootPath: URL(fileURLWithPath: "/tmp/bridge-refresh-unrelated"),
            paths: ["Unrelated.swift"],
            timestamp: .now,
            batchSeq: 51
        )
        let memberChangeset = FileChangeset(
            worktreeId: filesOnlyMember.id,
            repoId: filesOnlyMember.repoId,
            rootPath: filesOnlyMember.path,
            paths: ["Member.swift"],
            timestamp: .now,
            batchSeq: 52
        )

        // Act
        await fixture.controller.handleWorktreeProductInvalidation(.filesChanged(unrelatedChangeset))
        let afterUnrelated = fixture.controller.refreshAdmissionCoordinator.diagnosticSnapshot.dirtyFact
        await fixture.controller.handleWorktreeProductInvalidation(.filesChanged(memberChangeset))
        await fixture.controller.handleWorktreeProductInvalidation(
            .statusChanged(makeRefreshAdmissionStatus(branch: "member", changed: 1), worktreeId: filesOnlyMember.id)
        )

        // Assert
        #expect(afterUnrelated == nil)
        let dirtyFact = try #require(fixture.controller.refreshAdmissionCoordinator.diagnosticSnapshot.dirtyFact)
        #expect(dirtyFact.fileChangesets.map(\.worktreeId) == [filesOnlyMember.id])
        #expect(dirtyFact.latestFileStatus == nil)
        #expect(!dirtyFact.requiresReviewRefresh)
        await fixture.finish()
    }
}
