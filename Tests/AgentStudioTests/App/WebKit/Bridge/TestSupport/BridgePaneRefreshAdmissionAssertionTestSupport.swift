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

func waitForStartedComparisonCount(
    _ expectedCount: Int,
    gate: BridgeComparisonGate,
    maxTurns: Int = 2000
) async -> Bool {
    for _ in 0..<maxTurns {
        if await gate.hasStartedComparisonCount(expectedCount) {
            return true
        }
        await Task.yield()
    }
    return false
}

@MainActor
func waitForRetiringReviewRefreshTasksToDrain(
    _ controller: BridgePaneController,
    maxTurns: Int = 2000
) async -> Bool {
    for _ in 0..<maxTurns {
        if controller.retiringReviewRefreshTaskById.isEmpty {
            return true
        }
        await Task.yield()
    }
    return false
}

@MainActor
func waitForRetiringFileRefreshTasksToDrain(
    _ controller: BridgePaneController
) async -> Bool {
    await controller.worktreeRefreshDriver.awaitRetiringFileOperations()
    return !controller.worktreeRefreshDriver.hasRetiringFileOperations
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
func waitForActiveFileRefreshTaskToFinish(
    _ controller: BridgePaneController,
    maxTurns: Int = 2000
) async {
    for _ in 0..<maxTurns {
        if !controller.worktreeRefreshDriver.hasActiveFileOperation { return }
        await Task.yield()
    }
    Issue.record("Expected active Bridge File refresh task to finish")
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
@MainActor
func sealRefreshAdmissionFileProofBatch(
    _ fixture: RefreshAdmissionIntegrationFixture
) async throws -> BridgeProductBatchCompleteFrame {
    let installation = fixture.productInstallation
    let scopeBytes = try JSONSerialization.data(withJSONObject: [
        "kind": "subscription.setScope",
        "paneSessionId": installation.bootstrap.paneSessionId,
        "workerInstanceId": installation.bootstrap.workerInstanceId,
        "wireVersion": BridgeProductWireContract.version,
        "requestId": "request-file-proof-scope-refresh-admission",
        "requestSequence": 4,
        "subscriptionId": "file-subscription-refresh-admission",
        "subscriptionKind": "file.metadata",
        "domain": "default",
        "handle": "file-proof-handle-refresh-admission",
        "incarnation": "file-proof-incarnation-refresh-admission",
        "scopeRevision": 1,
        "scope": [
            "kind": "file",
            "changeFilter": ["kind": "none"],
            "interests": [],
            "pathScope": [],
        ] as [String: Any],
    ])
    let scopeRequest = try BridgeProductStrictJSON.decode(
        BridgeProductViewScopeRequest.self, from: scopeBytes
    )
    #expect(
        await installation.session.acceptViewScope(
            scopeRequest, productAdmission: fixture.productAdmission
        ) == nil
    )
    guard case .sourceAccepted(let accepted) = try refreshAdmissionFileSourceAcceptedEvent() else {
        throw RefreshAdmissionIntegrationError.expectedMetadataFrame
    }
    let snapshot = BridgeWorktreeFileKeyedSnapshot(
        memberStatus: .init(
            record: BridgeProductFileMemberStatusRecord(source: accepted.source),
            revision: 1
        ),
        records: [],
        targetRevision: 1,
        tombstoneRevisionByKey: [:],
        absenceFloorRevisionByRange: [:]
    )
    #expect(
        try await installation.session.sealFileSnapshot(
            subscriptionId: "file-subscription-refresh-admission",
            snapshot: snapshot,
            productAdmission: fixture.productAdmission
        )
    )
    guard case .batch(.begin(let begin)) = try await fixture.consumeNextMetadataFrame(),
        case .batch(.part(let part)) = try await fixture.consumeNextMetadataFrame(),
        case .put(let key, _, _) = part.part,
        case .batch(.complete(let complete)) = try await fixture.consumeNextMetadataFrame()
    else {
        throw RefreshAdmissionIntegrationError.expectedMetadataFrame
    }
    #expect(begin.mode == .snapshot)
    #expect(key == BridgeProductFileMemberStatusRecord.recordKey)
    #expect(complete.identity.batchId == begin.identity.batchId)
    return complete
}
