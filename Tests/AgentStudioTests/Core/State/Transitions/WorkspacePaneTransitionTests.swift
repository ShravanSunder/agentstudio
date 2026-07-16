import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace pane transitions")
struct WorkspacePaneTransitionTests {
    @Test("title planner produces one exact replacement without mutating its input")
    func titlePlannerProducesExactReplacement() throws {
        // Arrange
        let originalState = makePaneTransitionState(title: "Before")
        let request = WorkspacePaneTitleUpdateRequest(
            paneID: originalState.id,
            title: "After"
        )

        // Act
        let decision = WorkspacePaneTitleTransitionPlanner.plan(
            request,
            currentPaneState: originalState
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected one changed title transition")
            return
        }
        let replacement = try #require(transition.replacements.onlyElement)
        #expect(replacement.paneID == originalState.id)
        #expect(replacement.expectedCurrentState == originalState)
        #expect(replacement.replacementState.metadata.title == "After")
        #expect(replacement.replacementState.id == originalState.id)
        #expect(originalState.metadata.title == "Before")
    }

    @Test("title planner returns strict unchanged and missing decisions")
    func titlePlannerReturnsUnchangedAndMissingDecisions() {
        // Arrange
        let originalState = makePaneTransitionState(title: "Same")
        let missingPaneID = UUIDv7.generate()

        // Act / Assert
        #expect(
            WorkspacePaneTitleTransitionPlanner.plan(
                WorkspacePaneTitleUpdateRequest(
                    paneID: originalState.id,
                    title: "Same"
                ),
                currentPaneState: originalState
            ) == .unchanged
        )
        #expect(
            WorkspacePaneTitleTransitionPlanner.plan(
                WorkspacePaneTitleUpdateRequest(
                    paneID: missingPaneID,
                    title: "Missing"
                ),
                currentPaneState: nil
            ) == .rejected(.paneMissing(missingPaneID))
        )
    }

    @Test("zmx anchor planner batches accepted replacements and reports non-destructive skips")
    func zmxAnchorPlannerBatchesAcceptedReplacements() throws {
        // Arrange
        let changedPane = makePaneTransitionState(title: "Changed")
        let changedSessionID = makeValidMainSessionID(paneID: changedPane.id, seed: "1")
        let unchangedPaneID = UUIDv7.generate()
        let unchangedSessionID = makeValidMainSessionID(paneID: unchangedPaneID, seed: "2")
        let unchangedPane = makePaneTransitionState(
            paneID: unchangedPaneID,
            title: "Unchanged",
            zmxSessionID: unchangedSessionID
        )
        let nonZmxPane = PaneGraphState(
            pane: Pane(
                content: .terminal(TerminalState(provider: .ghostty, lifetime: .persistent)),
                metadata: PaneMetadata(title: "Direct")
            )
        )
        let missingPaneID = UUIDv7.generate()
        let requests = [
            WorkspacePaneZmxAnchorRepairRequest(
                paneID: changedPane.id,
                sessionID: changedSessionID
            ),
            WorkspacePaneZmxAnchorRepairRequest(
                paneID: unchangedPane.id,
                sessionID: unchangedSessionID
            ),
            WorkspacePaneZmxAnchorRepairRequest(
                paneID: nonZmxPane.id,
                sessionID: "agentstudio-direct"
            ),
            WorkspacePaneZmxAnchorRepairRequest(
                paneID: missingPaneID,
                sessionID: "agentstudio-missing"
            ),
        ]
        let currentStates = [
            changedPane.id: changedPane,
            unchangedPane.id: unchangedPane,
            nonZmxPane.id: nonZmxPane,
        ]

        // Act
        let decision = WorkspacePaneZmxAnchorRepairPlanner.plan(
            requests,
            currentPaneStateByID: currentStates
        )

        // Assert
        guard case .changed(let transition, let report) = decision else {
            Issue.record("expected a changed zmx-anchor batch")
            return
        }
        let replacement = try #require(transition.replacements.onlyElement)
        #expect(replacement.paneID == changedPane.id)
        #expect(replacement.expectedCurrentState == changedPane)
        #expect(zmxSessionID(in: replacement.replacementState) == changedSessionID)
        #expect(report.acceptedPaneIDs == [changedPane.id])
        #expect(report.unchangedPaneIDs == [unchangedPane.id])
        #expect(
            report.rejections
                == [
                    .init(
                        paneID: nonZmxPane.id,
                        reason: .providerMismatch(received: .ghostty)
                    ),
                    .init(paneID: missingPaneID, reason: .paneMissing),
                ]
        )
        #expect(zmxSessionID(in: changedPane) == nil)
    }

    @Test("zmx anchor planner rejects duplicate pane requests without accepting either value")
    func zmxAnchorPlannerRejectsDuplicatePaneRequests() {
        // Arrange
        let pane = makePaneTransitionState(title: "Duplicate")
        let requests = [
            WorkspacePaneZmxAnchorRepairRequest(paneID: pane.id, sessionID: "first"),
            WorkspacePaneZmxAnchorRepairRequest(paneID: pane.id, sessionID: "second"),
        ]

        // Act
        let decision = WorkspacePaneZmxAnchorRepairPlanner.plan(
            requests,
            currentPaneStateByID: [pane.id: pane]
        )

        // Assert
        #expect(
            decision
                == .unchanged(
                    WorkspacePaneZmxAnchorRepairReport(
                        acceptedPaneIDs: [],
                        unchangedPaneIDs: [],
                        rejections: [
                            .init(paneID: pane.id, reason: .duplicateRequest)
                        ]
                    )
                )
        )
        #expect(zmxSessionID(in: pane) == nil)
    }

    @Test("zmx anchor planner rejects mismatched keyed pane identity")
    func zmxAnchorPlannerRejectsMismatchedPaneIdentity() {
        // Arrange
        let requestedPaneID = UUIDv7.generate()
        let currentPane = makePaneTransitionState(title: "Foreign")

        // Act
        let decision = WorkspacePaneZmxAnchorRepairPlanner.plan(
            [
                .init(
                    paneID: requestedPaneID,
                    sessionID: makeValidMainSessionID(paneID: requestedPaneID, seed: "7")
                )
            ],
            currentPaneStateByID: [requestedPaneID: currentPane]
        )

        // Assert
        #expect(
            decision
                == .unchanged(
                    WorkspacePaneZmxAnchorRepairReport(
                        acceptedPaneIDs: [],
                        unchangedPaneIDs: [],
                        rejections: [
                            .init(
                                paneID: requestedPaneID,
                                reason: .paneIdentityMismatch(currentPaneID: currentPane.id)
                            )
                        ]
                    )
                )
        )
    }

    @Test("zmx anchor planner rejects a session identity for another pane")
    func zmxAnchorPlannerRejectsForeignSessionIdentity() {
        // Arrange
        let pane = makePaneTransitionState(title: "Target")
        let foreignSessionID = makeValidMainSessionID(
            paneID: UUIDv7.generate(),
            seed: "8"
        )

        // Act
        let decision = WorkspacePaneZmxAnchorRepairPlanner.plan(
            [.init(paneID: pane.id, sessionID: foreignSessionID)],
            currentPaneStateByID: [pane.id: pane]
        )

        // Assert
        #expect(
            decision
                == .unchanged(
                    WorkspacePaneZmxAnchorRepairReport(
                        acceptedPaneIDs: [],
                        unchangedPaneIDs: [],
                        rejections: [
                            .init(
                                paneID: pane.id,
                                reason: .sessionIDDoesNotMatchPaneKind
                            )
                        ]
                    )
                )
        )
    }
}

private func zmxSessionID(in paneState: PaneGraphState) -> String? {
    guard case .terminal(let terminalState) = paneState.content else { return nil }
    return terminalState.zmxSessionId
}

private func makePaneTransitionState(
    paneID: UUID = UUIDv7.generate(),
    title: String,
    zmxSessionID: String? = nil
) -> PaneGraphState {
    PaneGraphState(
        pane: Pane(
            id: paneID,
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionId: zmxSessionID
                )
            ),
            metadata: PaneMetadata(title: title)
        )
    )
}

private func makeValidMainSessionID(paneID: UUID, seed: Character) -> String {
    let stableKey = String(repeating: seed, count: 16)
    return ZmxBackend.sessionId(
        repoStableKey: stableKey,
        worktreeStableKey: stableKey,
        paneId: paneID
    )
}

extension Array {
    fileprivate var onlyElement: Element? {
        count == 1 ? self[0] : nil
    }
}
