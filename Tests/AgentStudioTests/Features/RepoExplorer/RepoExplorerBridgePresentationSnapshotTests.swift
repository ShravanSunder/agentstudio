import Foundation
import Testing

@testable import AgentStudio

@Suite("Repo Explorer Bridge presentation snapshot")
struct RepoExplorerBridgePresentationSnapshotTests {
    @Test("worktree rows read cached Bridge presentation without live command resolution")
    func worktreeRowsReadCachedBridgePresentation() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"
            ),
            encoding: .utf8
        )

        // Act
        let rendersFromProjectionSnapshot =
            source.contains("bridgeCommandResolution: cachedProjectionResult.snapshot")
            && source.contains(".bridgeCommandResolutionByWorktreeId[")
        let resolvesThroughDispatcher = source.contains(".bridgePaneCommandTarget(")

        // Assert
        #expect(rendersFromProjectionSnapshot)
        #expect(!resolvesThroughDispatcher)
    }

    @Test("snapshot preserves Bridge pane eligibility and resolver ordering")
    func snapshotPreservesBridgePaneEligibilityAndResolverOrdering() {
        // Arrange
        let repoId = UUID()
        let lowerPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let higherPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let fixtures = resolverParityFixtures(
            repoId: repoId,
            lowerPaneId: lowerPaneId,
            higherPaneId: higherPaneId
        )
        let repo = RepoPresentationItem(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: fixtures.map(\.worktree)
        )
        let candidatesByWorktreeId = Dictionary(
            uniqueKeysWithValues: fixtures.map { fixture in
                (
                    fixture.worktree.id,
                    fixture.candidates.map { candidate in
                        BridgePaneCommandCandidate(
                            paneId: candidate.paneId,
                            worktreeId: candidate.worktreeId ?? fixture.worktree.id,
                            isBridgePane: candidate.isBridgePane,
                            isPaneActive: candidate.isPaneActive,
                            isCurrentActivePane: candidate.isCurrentActivePane,
                            attendanceOrdinal: candidate.attendanceOrdinal,
                            tabIndex: candidate.tabIndex,
                            paneIndexInTab: candidate.paneIndexInTab
                        )
                    }
                )
            }
        )

        // Act
        let snapshot = RepoExplorerSnapshot(
            repos: [repo],
            repoEnrichmentByRepoId: [:],
            query: "",
            bridgePaneCommandCandidatesByWorktreeId: candidatesByWorktreeId
        )

        // Assert
        for fixture in fixtures {
            #expect(
                snapshot.bridgeCommandResolutionByWorktreeId[fixture.worktree.id]
                    == fixture.expectedResolution,
                "Failed Bridge presentation fixture: \(fixture.name)"
            )
        }
    }

    private func resolverParityFixtures(
        repoId: UUID,
        lowerPaneId: UUID,
        higherPaneId: UUID
    ) -> [ResolutionFixture] {
        [
            resolutionFixture(
                repoId: repoId,
                name: "attendance",
                candidates: [
                    candidate(paneId: UUID(), attendanceOrdinal: 4),
                    candidate(paneId: higherPaneId, attendanceOrdinal: 9),
                ],
                expectedResolution: .reuse(paneId: higherPaneId)
            ),
            resolutionFixture(
                repoId: repoId,
                name: "current-active-pane",
                candidates: [
                    candidate(paneId: lowerPaneId, attendanceOrdinal: 12, tabIndex: 0),
                    candidate(
                        paneId: higherPaneId,
                        isCurrentActivePane: true,
                        attendanceOrdinal: 12,
                        tabIndex: 1
                    ),
                ],
                expectedResolution: .reuse(paneId: higherPaneId)
            ),
            resolutionFixture(
                repoId: repoId,
                name: "tab-index",
                candidates: [
                    candidate(paneId: higherPaneId, tabIndex: 1),
                    candidate(paneId: lowerPaneId, tabIndex: 0),
                ],
                expectedResolution: .reuse(paneId: lowerPaneId)
            ),
            resolutionFixture(
                repoId: repoId,
                name: "pane-index",
                candidates: [
                    candidate(paneId: higherPaneId, paneIndexInTab: 2),
                    candidate(paneId: lowerPaneId, paneIndexInTab: 1),
                ],
                expectedResolution: .reuse(paneId: lowerPaneId)
            ),
            resolutionFixture(
                repoId: repoId,
                name: "pane-uuid",
                candidates: [
                    candidate(paneId: higherPaneId),
                    candidate(paneId: lowerPaneId),
                ],
                expectedResolution: .reuse(paneId: lowerPaneId)
            ),
            resolutionFixture(
                repoId: repoId,
                name: "create-when-ineligible",
                candidates: [
                    candidate(paneId: UUID(), worktreeId: UUID()),
                    candidate(paneId: UUID(), isBridgePane: false),
                    candidate(paneId: UUID(), isPaneActive: false),
                ],
                expectedResolution: .create
            ),
        ]
    }

    @Test("presentation-changing runtime facts invalidate snapshot equality")
    func presentationChangingRuntimeFactsInvalidateSnapshotEquality() {
        // Arrange
        let repoId = UUID()
        let worktree = Worktree(
            repoId: repoId,
            name: "main",
            path: URL(fileURLWithPath: "/tmp/agent-studio"),
            isMainWorktree: true
        )
        let repo = RepoPresentationItem(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: [worktree]
        )
        let preferredPaneId = UUID()
        let fallbackPaneId = UUID()
        let preferredCandidate = BridgePaneCommandCandidate(
            paneId: preferredPaneId,
            worktreeId: worktree.id,
            isBridgePane: true,
            isPaneActive: true,
            isCurrentActivePane: true,
            attendanceOrdinal: 1,
            tabIndex: 1,
            paneIndexInTab: 0
        )
        let fallbackCandidate = BridgePaneCommandCandidate(
            paneId: fallbackPaneId,
            worktreeId: worktree.id,
            isBridgePane: true,
            isPaneActive: true,
            isCurrentActivePane: false,
            attendanceOrdinal: 1,
            tabIndex: 0,
            paneIndexInTab: 0
        )
        let baseline = snapshot(
            repo: repo,
            worktreeId: worktree.id,
            candidates: [preferredCandidate, fallbackCandidate]
        )
        let attendanceChanged = snapshot(
            repo: repo,
            worktreeId: worktree.id,
            candidates: [
                preferredCandidate,
                replacing(fallbackCandidate, attendanceOrdinal: 2),
            ]
        )
        let activePaneChanged = snapshot(
            repo: repo,
            worktreeId: worktree.id,
            candidates: [
                replacing(preferredCandidate, isCurrentActivePane: false),
                replacing(fallbackCandidate, isCurrentActivePane: true),
            ]
        )
        let contentChanged = snapshot(
            repo: repo,
            worktreeId: worktree.id,
            candidates: [
                replacing(preferredCandidate, isBridgePane: false),
                fallbackCandidate,
            ]
        )
        let residencyChanged = snapshot(
            repo: repo,
            worktreeId: worktree.id,
            candidates: [
                replacing(preferredCandidate, isPaneActive: false),
                fallbackCandidate,
            ]
        )

        // Act / Assert
        #expect(baseline.bridgeCommandResolutionByWorktreeId[worktree.id] == .reuse(paneId: preferredPaneId))
        #expect(attendanceChanged.bridgeCommandResolutionByWorktreeId[worktree.id] == .reuse(paneId: fallbackPaneId))
        #expect(activePaneChanged.bridgeCommandResolutionByWorktreeId[worktree.id] == .reuse(paneId: fallbackPaneId))
        #expect(contentChanged.bridgeCommandResolutionByWorktreeId[worktree.id] == .reuse(paneId: fallbackPaneId))
        #expect(residencyChanged.bridgeCommandResolutionByWorktreeId[worktree.id] == .reuse(paneId: fallbackPaneId))
        #expect(baseline != attendanceChanged)
        #expect(baseline != activePaneChanged)
        #expect(baseline != contentChanged)
        #expect(baseline != residencyChanged)
    }

    private struct CandidateFixture {
        let paneId: UUID
        let worktreeId: UUID?
        let isBridgePane: Bool
        let isPaneActive: Bool
        let isCurrentActivePane: Bool
        let attendanceOrdinal: UInt64?
        let tabIndex: Int
        let paneIndexInTab: Int
    }

    private struct ResolutionFixture {
        let name: String
        let worktree: Worktree
        let candidates: [CandidateFixture]
        let expectedResolution: BridgePaneCommandResolution
    }

    private func resolutionFixture(
        repoId: UUID,
        name: String,
        candidates: [CandidateFixture],
        expectedResolution: BridgePaneCommandResolution
    ) -> ResolutionFixture {
        ResolutionFixture(
            name: name,
            worktree: Worktree(
                repoId: repoId,
                name: name,
                path: URL(fileURLWithPath: "/tmp/agent-studio.\(name)")
            ),
            candidates: candidates,
            expectedResolution: expectedResolution
        )
    }

    private func candidate(
        paneId: UUID,
        worktreeId: UUID? = nil,
        isBridgePane: Bool = true,
        isPaneActive: Bool = true,
        isCurrentActivePane: Bool = false,
        attendanceOrdinal: UInt64? = nil,
        tabIndex: Int = 0,
        paneIndexInTab: Int = 0
    ) -> CandidateFixture {
        CandidateFixture(
            paneId: paneId,
            worktreeId: worktreeId,
            isBridgePane: isBridgePane,
            isPaneActive: isPaneActive,
            isCurrentActivePane: isCurrentActivePane,
            attendanceOrdinal: attendanceOrdinal,
            tabIndex: tabIndex,
            paneIndexInTab: paneIndexInTab
        )
    }

    private func snapshot(
        repo: RepoPresentationItem,
        worktreeId: UUID,
        candidates: [BridgePaneCommandCandidate]
    ) -> RepoExplorerSnapshot {
        RepoExplorerSnapshot(
            repos: [repo],
            repoEnrichmentByRepoId: [:],
            query: "",
            bridgePaneCommandCandidatesByWorktreeId: [worktreeId: candidates]
        )
    }

    private func replacing(
        _ candidate: BridgePaneCommandCandidate,
        isBridgePane: Bool? = nil,
        isPaneActive: Bool? = nil,
        isCurrentActivePane: Bool? = nil,
        attendanceOrdinal: UInt64? = nil
    ) -> BridgePaneCommandCandidate {
        BridgePaneCommandCandidate(
            paneId: candidate.paneId,
            worktreeId: candidate.worktreeId,
            isBridgePane: isBridgePane ?? candidate.isBridgePane,
            isPaneActive: isPaneActive ?? candidate.isPaneActive,
            isCurrentActivePane: isCurrentActivePane ?? candidate.isCurrentActivePane,
            attendanceOrdinal: attendanceOrdinal ?? candidate.attendanceOrdinal,
            tabIndex: candidate.tabIndex,
            paneIndexInTab: candidate.paneIndexInTab
        )
    }
}
