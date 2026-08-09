import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Workspace pane comparison intent", .serialized)
struct WorkspacePaneComparisonIntentTests {
    @Test("typed Bridge pane-state mutation replaces only the addressed Bridge pane")
    func typedBridgePaneStateMutationUpdatesCanonicalGraph() throws {
        // Arrange
        let paneAtom = WorkspacePaneAtom()
        let pane = try #require(
            paneAtom.createPane(
                content: .bridgePanel(selectionRequiredBridgeState),
                metadata: bridgePaneMetadata
            )
        )
        let updatedState = BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(
                rootPath: "/tmp/comparison-intent",
                baseline: .staged
            )
        )

        // Act
        let result = paneAtom.updateBridgePaneState(pane.id, state: updatedState)

        // Assert
        #expect(result == .applied(updatedState))
        #expect(paneAtom.pane(pane.id)?.content == .bridgePanel(updatedState))
    }

    @Test("reviewer target wins when an automatic default arrives late")
    func explicitReviewerTargetWinsLateAutomaticDefault() throws {
        // Arrange
        let paneAtom = WorkspacePaneAtom()
        let pane = try #require(
            paneAtom.createPane(
                content: .bridgePanel(selectionRequiredBridgeState),
                metadata: bridgePaneMetadata
            )
        )
        let reviewerBaseline = WorkspaceBaseline.originDefaultBranch(
            remoteName: "upstream",
            branchName: "release"
        )
        let reviewerState = BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(
                rootPath: "/tmp/comparison-intent",
                baseline: reviewerBaseline
            )
        )
        #expect(
            paneAtom.updateBridgePaneState(pane.id, state: reviewerState)
                == .applied(reviewerState)
        )

        // Act
        let lateDefaultResult = paneAtom.setInitialBridgeContributionTargetIfAbsent(
            pane.id,
            target: .localDefaultBranch(branchName: "main")
        )

        // Assert
        #expect(lateDefaultResult == .unchanged(reviewerState))
        #expect(paneAtom.pane(pane.id)?.content == .bridgePanel(reviewerState))
    }

    @Test("initial contribution target is set once and returned canonically")
    func initialContributionTargetIsAppliedOnce() throws {
        // Arrange
        let paneAtom = WorkspacePaneAtom()
        let pane = try #require(
            paneAtom.createPane(
                content: .bridgePanel(selectionRequiredBridgeState),
                metadata: bridgePaneMetadata
            )
        )
        let initialTarget = WorkspaceReviewContributionTarget.localDefaultBranch(
            branchName: "master"
        )
        let expectedState = BridgePaneState(
            panelKind: .fileViewer,
            source: .workspace(
                rootPath: "/tmp/comparison-intent",
                baseline: WorkspaceBaseline(contributionTarget: initialTarget)
            )
        )

        // Act
        let firstResult = paneAtom.setInitialBridgeContributionTargetIfAbsent(
            pane.id,
            target: initialTarget
        )
        let repeatedResult = paneAtom.setInitialBridgeContributionTargetIfAbsent(
            pane.id,
            target: .branch(name: "late/default")
        )

        // Assert
        #expect(firstResult == .applied(expectedState))
        #expect(repeatedResult == .unchanged(expectedState))
        #expect(paneAtom.pane(pane.id)?.content == .bridgePanel(expectedState))
    }

    private var selectionRequiredBridgeState: BridgePaneState {
        BridgePaneState(
            panelKind: .fileViewer,
            source: .workspace(
                rootPath: "/tmp/comparison-intent",
                baseline: nil
            )
        )
    }

    private var bridgePaneMetadata: PaneMetadata {
        let root = URL(filePath: "/tmp/comparison-intent", directoryHint: .isDirectory)
        return PaneMetadata(
            paneId: PaneId(existingUUID: UUIDv7.generate()),
            contentType: .diff,
            launchDirectory: root,
            title: "Comparison intent",
            facets: PaneContextFacets(cwd: root)
        )
    }
}
