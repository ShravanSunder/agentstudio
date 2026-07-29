import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge

func refreshAdmissionFileSourceAcceptedEvent() throws -> BridgeProductFileMetadataEvent {
    .sourceAccepted(
        .init(
            source: try .init(
                repoId: "00000000-0000-4000-8000-000000000001",
                rootRevisionToken: "root-token-refresh-admission",
                sourceCursor: "source-cursor-refresh-admission",
                sourceId: "file-source-refresh-admission",
                subscriptionGeneration: 1,
                worktreeId: "00000000-0000-4000-8000-000000000002"
            )
        )
    )
}

func waitForRefreshAdmissionQueuedMetadataFrame(
    _ fixture: RefreshAdmissionIntegrationFixture,
    maxTurns: Int = 200
) async -> Bool {
    for _ in 0..<maxTurns {
        if await fixture.productInstallation.session.producerSnapshot().queuedFrameCount > 0 {
            return true
        }
        await Task.yield()
    }
    return false
}

@MainActor
func waitForRefreshAdmissionIdle(
    _ controller: BridgePaneController,
    maxTurns: Int = 2000
) async {
    for _ in 0..<maxTurns {
        let snapshot = controller.refreshAdmissionCoordinator.diagnosticSnapshot
        if snapshot.activeRefreshPass == nil, snapshot.dirtyFact == nil {
            return
        }
        await Task.yield()
    }
    Issue.record("Expected foreground Bridge refresh admission to become idle")
}

@MainActor
func waitForActiveReviewRefreshTaskToFinish(
    _ controller: BridgePaneController,
    maxTurns: Int = 2000
) async {
    for _ in 0..<maxTurns {
        if controller.activeReviewRefreshTask == nil {
            return
        }
        await Task.yield()
    }
    Issue.record("Expected active Bridge Review refresh task to finish")
}

@MainActor
func waitForRefreshAdmissionSettledWhileHidden(
    _ controller: BridgePaneController,
    maxTurns: Int = 2000
) async {
    for _ in 0..<maxTurns {
        let snapshot = controller.refreshAdmissionCoordinator.diagnosticSnapshot
        if snapshot.activity == .loadedHidden,
            snapshot.activeRefreshPass == nil,
            snapshot.dirtyFact != nil,
            controller.activeReviewRefreshTask == nil
        {
            return
        }
        await Task.yield()
    }
    Issue.record("Expected loaded-hidden Bridge refresh admission to retain one dirty fact")
}

func makeRefreshAdmissionStatus(
    branch: String,
    changed: Int
) -> GitWorkingTreeStatus {
    GitWorkingTreeStatus(
        summary: GitWorkingTreeSummary(
            changed: changed,
            staged: 0,
            untracked: 0
        ),
        branch: branch,
        origin: nil
    )
}
