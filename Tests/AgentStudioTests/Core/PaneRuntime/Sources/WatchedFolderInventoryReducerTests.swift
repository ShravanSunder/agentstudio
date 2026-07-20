import Foundation
import Testing

@testable import AgentStudio

@Suite("Watched-folder inventory reducer")
struct WatchedFolderInventoryReducerTests {
    @Test("authoritative complete evidence replaces inventory and removes missing repositories")
    func authoritativeCompleteReplacesInventory() {
        let inventory = InventoryFixture()

        let reduction = WatchedFolderInventoryReducer.reduce(
            previousGroups: inventory.previousGroups,
            scannerResult: inventory.completeResult(entries: [inventory.cloneEntry(inventory.repoA)]),
            mayReplaceNegativeSpace: true
        )

        #expect(
            reduction
                == .authoritativeReplacement(
                    WatchedFolderInventoryMutation(
                        repoGroups: [inventory.group(inventory.repoA)],
                        changedRepositories: [inventory.discovered(inventory.repoA)],
                        removedClonePaths: [inventory.repoB]
                    )
                )
        )
    }

    @Test("complete evidence without negative-space authority is additive")
    func completeWithoutNegativeSpaceAuthorityIsAdditive() {
        let inventory = InventoryFixture()

        let reduction = WatchedFolderInventoryReducer.reduce(
            previousGroups: inventory.previousGroups,
            scannerResult: inventory.completeResult(entries: [inventory.cloneEntry(inventory.repoA)]),
            mayReplaceNegativeSpace: false
        )

        #expect(
            reduction
                == .additiveMerge(
                    WatchedFolderInventoryMutation(
                        repoGroups: inventory.previousGroups,
                        changedRepositories: [],
                        removedClonePaths: []
                    )
                )
        )
    }

    @Test("partial evidence unions linked worktrees and cannot express absence")
    func partialEvidenceStrictlyUnionsInventory() {
        let inventory = InventoryFixture()
        let entries = inventory.additiveEntries

        let reduction = WatchedFolderInventoryReducer.reduce(
            previousGroups: inventory.previousGroups,
            scannerResult: .partial(
                PartialRepoScan(
                    verifiedEntries: entries,
                    failures: NonEmptyScanFailures(
                        first: .scannerServiceFailed(detail: "partial fixture"),
                        remaining: []
                    ),
                    counts: inventory.emptyCounts,
                    serviceMetrics: .zero
                )
            ),
            mayReplaceNegativeSpace: true
        )

        #expect(reduction == .additiveMerge(inventory.expectedAdditiveMutation))
    }

    @Test("cancelled evidence follows the same strict union rule")
    func cancelledEvidenceStrictlyUnionsInventory() {
        let inventory = InventoryFixture()

        let reduction = WatchedFolderInventoryReducer.reduce(
            previousGroups: inventory.previousGroups,
            scannerResult: .cancelled(
                CancelledRepoScan(
                    verifiedEntries: inventory.additiveEntries,
                    counts: inventory.emptyCounts,
                    serviceMetrics: .zero
                )
            ),
            mayReplaceNegativeSpace: true
        )

        #expect(reduction == .additiveMerge(inventory.expectedAdditiveMutation))
    }

    @Test("unavailable evidence preserves inventory")
    func unavailableEvidencePreservesInventory() {
        let inventory = InventoryFixture()

        let reduction = WatchedFolderInventoryReducer.reduce(
            previousGroups: inventory.previousGroups,
            scannerResult: .unavailable(
                UnavailableRepoScan(
                    reason: .rootDoesNotExist,
                    counts: inventory.emptyCounts,
                    serviceMetrics: .zero
                )
            ),
            mayReplaceNegativeSpace: true
        )

        #expect(reduction == .preserved)
    }

    @Test("failed evidence preserves inventory")
    func failedEvidencePreservesInventory() {
        let inventory = InventoryFixture()

        let reduction = WatchedFolderInventoryReducer.reduce(
            previousGroups: inventory.previousGroups,
            scannerResult: .failed(
                FailedRepoScan(
                    reason: .scannerServiceFailed(detail: "failed fixture"),
                    counts: inventory.emptyCounts,
                    serviceMetrics: .zero
                )
            ),
            mayReplaceNegativeSpace: true
        )

        #expect(reduction == .preserved)
    }
}

private struct InventoryFixture {
    let repoA = URL(fileURLWithPath: "/watched-folder-reducer/repo-a")
    let repoB = URL(fileURLWithPath: "/watched-folder-reducer/repo-b")
    let repoC = URL(fileURLWithPath: "/watched-folder-reducer/repo-c")
    let existingLinkedA = URL(fileURLWithPath: "/watched-folder-reducer/repo-a-existing")
    let discoveredLinkedA = URL(fileURLWithPath: "/watched-folder-reducer/repo-a-new")

    var previousGroups: [RepoScanner.RepoScanGroup] {
        [
            group(repoA, linkedWorktreePaths: [existingLinkedA]),
            group(repoB),
        ]
    }

    var additiveEntries: [RepoScanner.ResolvedGitEntry] {
        [
            cloneEntry(repoA),
            linkedEntry(discoveredLinkedA, parentClonePath: repoA),
            cloneEntry(repoC),
        ]
    }

    var expectedAdditiveMutation: WatchedFolderInventoryMutation {
        WatchedFolderInventoryMutation(
            repoGroups: [
                group(repoA, linkedWorktreePaths: [existingLinkedA, discoveredLinkedA]),
                group(repoB),
                group(repoC),
            ],
            changedRepositories: [
                discovered(
                    repoA,
                    linkedWorktreePaths: [existingLinkedA, discoveredLinkedA]
                ),
                discovered(repoC),
            ],
            removedClonePaths: []
        )
    }

    var emptyCounts: RepoScannerEvidenceCounts {
        RepoScannerEvidenceCounts(
            directoryVisitCount: 0,
            directoryTraversalFailureCount: 0,
            entryMetadataFailureCount: 0,
            gitCandidateCount: 0,
            validationSuccessCount: 0,
            validationAuthoritativeNegativeCount: 0,
            validationTimeoutCount: 0,
            validationCancellationCount: 0,
            validationFailureCount: 0,
            scannerServiceInvocationCount: 1
        )
    }

    func completeResult(entries: [RepoScanner.ResolvedGitEntry]) -> RepoScannerResult {
        .completeAuthoritative(
            CompleteRepoScan(
                verifiedEntries: entries,
                counts: emptyCounts,
                serviceMetrics: .zero
            )
        )
    }

    func group(
        _ clonePath: URL,
        linkedWorktreePaths: [URL] = []
    ) -> RepoScanner.RepoScanGroup {
        RepoScanner.RepoScanGroup(
            clonePath: clonePath,
            linkedWorktreePaths: linkedWorktreePaths
        )
    }

    func discovered(
        _ repoPath: URL,
        linkedWorktreePaths: [URL] = []
    ) -> DiscoveredRepoTopologyInfo {
        DiscoveredRepoTopologyInfo(
            repoPath: repoPath,
            linkedWorktrees: .scanned(linkedWorktreePaths)
        )
    }

    func cloneEntry(_ path: URL) -> RepoScanner.ResolvedGitEntry {
        RepoScanner.ResolvedGitEntry(
            path: path,
            kind: .cloneRoot,
            repositoryKey: path.path
        )
    }

    func linkedEntry(
        _ path: URL,
        parentClonePath: URL
    ) -> RepoScanner.ResolvedGitEntry {
        RepoScanner.ResolvedGitEntry(
            path: path,
            kind: .linkedWorktree(parentClonePath: parentClonePath),
            repositoryKey: parentClonePath.path
        )
    }
}
