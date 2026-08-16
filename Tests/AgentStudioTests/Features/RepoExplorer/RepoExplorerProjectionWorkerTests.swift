import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("RepoExplorerProjectionWorker")
struct RepoExplorerProjectionWorkerTests {
    private enum CancellationProbe: Error {
        case cancelled
    }

    @Test("one rendered repo favorite change is classified as a scoped row delta")
    func renderedRepoFavoriteChangeIsScoped() {
        let repoId = UUID()
        let initialRepo = repo(id: repoId, name: "agent-studio")
        let before = request(repos: [initialRepo])
        let after = request(repos: [withFavorite(initialRepo)])

        #expect(after.scopedChange(from: before) == .repo(repoId))
    }

    @Test("scoped favorite projection matches the full reference without whole-surface projection")
    func scopedFavoriteProjectionMatchesReference() throws {
        let repoId = UUID()
        let initialRepo = repo(id: repoId, name: "agent-studio")
        let before = request(repos: [initialRepo])
        let after = request(repos: [withFavorite(initialRepo)])
        let previous = try RepoExplorerProjectionWorker.project(before)

        let scoped = try #require(
            RepoExplorerProjectionWorker.applyScopedChange(.repo(repoId), request: after, previous: previous)
        )
        let reference = try RepoExplorerProjectionWorker.project(after)

        #expect(scoped.projection == reference.projection)
        #expect(scoped.rowIndex == reference.rowIndex)
    }

    @Test("successive scoped favorite changes preserve full reference ordering")
    func successiveScopedFavoriteChangesPreserveReferenceOrdering() throws {
        let alphaRepo = repo(id: UUID(), name: "alpha")
        let bravoRepo = repo(id: UUID(), name: "bravo")
        let charlieRepo = repo(id: UUID(), name: "charlie")
        let initialRequest = request(repos: [alphaRepo, bravoRepo, charlieRepo])
        let charlieFavoriteRequest = request(
            repos: [alphaRepo, bravoRepo, withFavorite(charlieRepo)]
        )
        let alphaAndCharlieFavoriteRequest = request(
            repos: [withFavorite(alphaRepo), bravoRepo, withFavorite(charlieRepo)]
        )
        let initialProjection = try RepoExplorerProjectionWorker.project(initialRequest)
        let charlieFavoriteProjection = try #require(
            RepoExplorerProjectionWorker.applyScopedChange(
                .repo(charlieRepo.id),
                request: charlieFavoriteRequest,
                previous: initialProjection
            )
        )

        let scopedProjection = try #require(
            RepoExplorerProjectionWorker.applyScopedChange(
                .repo(alphaRepo.id),
                request: alphaAndCharlieFavoriteRequest,
                previous: charlieFavoriteProjection
            )
        )
        let referenceProjection = try RepoExplorerProjectionWorker.project(
            alphaAndCharlieFavoriteRequest
        )

        #expect(scopedProjection.projection == referenceProjection.projection)
        #expect(scopedProjection.rowIndex.entries == referenceProjection.rowIndex.entries)
    }

    @Test("worker projects sidebar model and row index off caller isolation")
    func workerProjectsSidebarModelAndRowIndex() async throws {
        let repoId = UUID()
        let matchingWorktree = Worktree(
            repoId: repoId,
            name: "feature",
            path: URL(fileURLWithPath: "/tmp/feature"),
            isMainWorktree: false
        )
        let filteredWorktree = Worktree(
            repoId: repoId,
            name: "main",
            path: URL(fileURLWithPath: "/tmp/main"),
            isMainWorktree: true
        )
        let repo = RepoPresentationItem(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: [filteredWorktree, matchingWorktree]
        )
        let snapshot = RepoExplorerSnapshot(
            repos: [repo],
            repoEnrichmentByRepoId: [
                repoId: .resolvedRemote(
                    repoId: repoId,
                    raw: RawRepoOrigin(origin: "git@github.com:askluna/agent-studio.git", upstream: nil),
                    identity: RepoIdentity(
                        groupKey: "remote:askluna/agent-studio",
                        remoteSlug: "askluna/agent-studio",
                        organizationName: "askluna",
                        displayName: "agent-studio"
                    ),
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
            ],
            groupingMode: .repo,
            sortOrder: .ascending,
            query: "feature"
        )
        let request = RepoExplorerProjectionRequest(
            generation: 3,
            snapshot: snapshot,
            collapsedGroupIds: [],
            isFiltering: true,
            trigger: .search
        )

        let result = try await RepoExplorerProjectionWorker().project(request)

        #expect(result.generation == 3)
        #expect(result.snapshot == snapshot)
        #expect(result.trigger == .search)
        #expect(result.rowIndex.entries.count == 3)
        let visibleWorktreeIds = result.projection.resolvedGroups.first?.repos.first?.worktrees.map { $0.id }
        #expect(visibleWorktreeIds == [matchingWorktree.id])
        #expect(result.branchNameByWorktreeId[matchingWorktree.id] == "Unknown branch")
    }

    @Test("worker preserves favorites-first section ordering off caller isolation")
    func workerPreservesFavoritesFirstSectionOrdering() async throws {
        let normalRepoId = UUID()
        let favoriteRepoId = UUID()
        let normalRepo = repo(id: normalRepoId, name: "alpha-normal")
        let favoriteRepo = repo(id: favoriteRepoId, name: "zeta-favorite", isFavorite: true)
        let snapshot = RepoExplorerSnapshot(
            repos: [normalRepo, favoriteRepo],
            repoEnrichmentByRepoId: [
                normalRepoId: resolvedRemote(repoId: normalRepoId, displayName: "alpha-normal"),
                favoriteRepoId: resolvedRemote(repoId: favoriteRepoId, displayName: "zeta-favorite"),
            ],
            groupingMode: .repo,
            sortOrder: .ascending,
            query: ""
        )
        let request = RepoExplorerProjectionRequest(
            generation: 4,
            snapshot: snapshot,
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .startupDiagnostic
        )

        let result = try await RepoExplorerProjectionWorker().project(request)

        #expect(result.generation == 4)
        #expect(result.snapshot == snapshot)
        #expect(result.projection.sections.map(\.kind) == [.favorites, .repositories])
        #expect(result.projection.resolvedGroups.map(\.repoTitle) == ["zeta-favorite", "alpha-normal"])
        #expect(result.projection.resolvedGroups.flatMap(\.repos).map(\.id) == [favoriteRepoId, normalRepoId])
        #expect(result.rowIndex.entries.count == 6)
    }

    @Test("eager projection seam produces the complete result synchronously")
    func eagerProjectionSeamProducesCompleteResultSynchronously() throws {
        let repoId = UUID()
        let repo = repo(id: repoId, name: "agent-studio")
        let snapshot = RepoExplorerSnapshot(
            repos: [repo],
            repoEnrichmentByRepoId: [
                repoId: resolvedRemote(repoId: repoId, displayName: "agent-studio")
            ],
            groupingMode: .repo,
            sortOrder: .ascending,
            query: ""
        )
        let request = RepoExplorerProjectionRequest(
            generation: 7,
            snapshot: snapshot,
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .dataRefresh
        )

        let result = try RepoExplorerProjectionWorker.project(request)

        #expect(result.generation == 7)
        #expect(result.snapshot == snapshot)
        #expect(
            result.rowIndex.entries.map(\.id) == [
                "section-header:repositories",
                "group:repo:\(repoId.uuidString)",
                "worktree:repo:\(repoId.uuidString):\(repoId.uuidString):\(repo.worktrees[0].id.uuidString):inactive",
            ])
        #expect(result.branchNameByWorktreeId[repo.worktrees[0].id] == "Unknown branch")
    }

    @Test("generated requests preserve pane and tab presentation facts")
    func generatedRequestPreservesPaneAndTabPresentationFacts() {
        let paneId = UUIDv7.generate()
        let tabId = UUIDv7.generate()
        let paneFacts = RepoExplorerPaneRowFacts(
            terminalTitle: "tests running",
            recencyReferenceDate: Date(timeIntervalSince1970: 100),
            recencyText: "2m",
            isActive: true
        )
        let tabFacts = RepoExplorerTabGroupFacts(displayTitle: "Implementation")
        let request = RepoExplorerProjectionRequest(
            generation: 0,
            snapshot: .init(repos: [], repoEnrichmentByRepoId: [:], groupingMode: .tab, query: ""),
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .startupDiagnostic,
            paneRowFactsByPaneId: [paneId: paneFacts],
            tabGroupFactsByTabId: [tabId: tabFacts]
        )

        let generatedRequest = request.generated(
            generation: 7,
            trigger: .dataRefresh
        )

        #expect(generatedRequest.generation == 7)
        #expect(generatedRequest.trigger == .dataRefresh)
        #expect(generatedRequest.paneRowFactsByPaneId == [paneId: paneFacts])
        #expect(generatedRequest.tabGroupFactsByTabId == [tabId: tabFacts])
    }

    @Test("worker resolves Bridge command candidates off the capture path")
    func workerResolvesBridgeCommandCandidates() throws {
        let repoId = UUID()
        let worktreeId = UUID()
        let paneId = UUID()
        let worktree = Worktree(
            id: worktreeId,
            repoId: repoId,
            name: "feature",
            path: URL(fileURLWithPath: "/tmp/feature")
        )
        let snapshot = RepoExplorerSnapshot(
            repos: [
                RepoPresentationItem(
                    id: repoId,
                    name: "agent-studio",
                    repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
                    stableKey: "agent-studio",
                    worktrees: [worktree]
                )
            ],
            repoEnrichmentByRepoId: [:],
            query: "",
            bridgePaneCommandCandidatesByWorktreeId: [
                worktreeId: [
                    BridgePaneCommandCandidate(
                        paneId: paneId,
                        worktreeId: worktreeId,
                        isBridgePane: true,
                        isPaneActive: true,
                        isCurrentActivePane: true,
                        attendanceOrdinal: 1,
                        tabIndex: 0,
                        paneIndexInTab: 0
                    )
                ]
            ]
        )
        let request = RepoExplorerProjectionRequest(
            generation: 8,
            snapshot: snapshot,
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .dataRefresh
        )

        let result = try RepoExplorerProjectionWorker.project(request)

        #expect(result.bridgeCommandResolutionByWorktreeId[worktreeId] == .reuse(paneId: paneId))
    }

    @Test("projection checks cancellation periodically within placement work")
    func projectionChecksCancellationWithinPlacementWork() {
        let repoId = UUID()
        let worktrees = (0..<600).map { index in
            Worktree(
                repoId: repoId,
                name: "worktree-\(index)",
                path: URL(fileURLWithPath: "/tmp/worktree-\(index)")
            )
        }
        let snapshot = RepoExplorerSnapshot(
            repos: [
                RepoPresentationItem(
                    id: repoId,
                    name: "agent-studio",
                    repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
                    stableKey: "agent-studio",
                    worktrees: worktrees
                )
            ],
            repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId, displayName: "agent-studio")],
            groupingMode: .tab,
            query: "",
            paneLocationsByWorktreeId: Dictionary(
                uniqueKeysWithValues: worktrees.map { worktree in
                    (
                        worktree.id,
                        [
                            WorkspacePaneLocation(
                                paneId: UUID(),
                                tabId: UUID(),
                                tabIndex: 0,
                                paneIndexInTab: 0,
                                isActiveInTab: true
                            )
                        ]
                    )
                }
            )
        )
        var checkpointCount = 0

        #expect(throws: CancellationProbe.cancelled) {
            _ = try RepoExplorerProjection.projectCancellable(snapshot) {
                checkpointCount += 1
                if checkpointCount == 3 { throw CancellationProbe.cancelled }
            }
        }
        #expect(checkpointCount == 3)
    }

    @Test("keyed eager sequence matches the ungated reference through removal and restoration")
    @MainActor
    func keyedEagerSequenceMatchesUngatedReference() async throws {
        let repoId = UUID()
        let initialRepo = repo(id: repoId, name: "agent-studio")
        let addedRepo = repo(id: UUID(), name: "agent-vm", isFavorite: true)
        let snapshots = [
            RepoExplorerSnapshot(
                repos: [initialRepo],
                repoEnrichmentByRepoId: [
                    repoId: resolvedRemote(repoId: repoId, displayName: "agent-studio")
                ],
                groupingMode: .repo,
                sortOrder: .ascending,
                query: ""
            ),
            RepoExplorerSnapshot(
                repos: [addedRepo, initialRepo],
                repoEnrichmentByRepoId: [
                    repoId: resolvedRemote(repoId: repoId, displayName: "agent-studio"),
                    addedRepo.id: resolvedRemote(repoId: addedRepo.id, displayName: "agent-vm"),
                ],
                groupingMode: .repo,
                sortOrder: .ascending,
                query: ""
            ),
            RepoExplorerSnapshot(
                repos: [addedRepo],
                repoEnrichmentByRepoId: [
                    addedRepo.id: resolvedRemote(repoId: addedRepo.id, displayName: "agent-vm")
                ],
                groupingMode: .repo,
                sortOrder: .ascending,
                query: ""
            ),
            RepoExplorerSnapshot(
                repos: [initialRepo, addedRepo],
                repoEnrichmentByRepoId: [
                    repoId: resolvedRemote(repoId: repoId, displayName: "agent-studio"),
                    addedRepo.id: resolvedRemote(repoId: addedRepo.id, displayName: "agent-vm"),
                ],
                groupingMode: .repo,
                sortOrder: .descending,
                query: ""
            ),
        ]
        let adapter = RepoExplorerProjectionAdapter()
        defer { adapter.stop() }

        for (offset, snapshot) in snapshots.enumerated() {
            let request = RepoExplorerProjectionRequest(
                generation: offset + 1,
                snapshot: snapshot,
                collapsedGroupIds: [],
                isFiltering: false,
                trigger: .dataRefresh
            )
            let referenceProjection = RepoExplorerProjection.project(snapshot)
            let referenceRows = RepoExplorerRowIndex(
                projection: referenceProjection,
                collapsedGroupIds: [],
                isFiltering: false
            )

            adapter.admit(request)
            for _ in 0..<10_000
            where adapter.publishedResult?.generation != request.generation {
                await Task.yield()
            }
            let result = try #require(adapter.publishedResult)
            #expect(result.generation == request.generation)
            #expect(result.projection == referenceProjection)
            #expect(result.rowIndex.entries.map(\.id) == referenceRows.entries.map(\.id))
        }

        let finalResult = adapter.publishedResult
        adapter.stop()
        adapter.admit(
            RepoExplorerProjectionRequest(
                generation: 99,
                snapshot: .init(repos: [], repoEnrichmentByRepoId: [:], groupingMode: .repo, query: ""),
                collapsedGroupIds: [],
                isFiltering: false,
                trigger: .dataRefresh
            )
        )
        for _ in 0..<100 { await Task.yield() }
        #expect(adapter.publishedResult == finalResult)
    }

    private func repo(id: UUID, name: String, isFavorite: Bool = false) -> RepoPresentationItem {
        RepoPresentationItem(
            id: id,
            name: name,
            repoPath: URL(fileURLWithPath: "/tmp/\(name)"),
            stableKey: name,
            isFavorite: isFavorite,
            worktrees: [
                Worktree(
                    repoId: id,
                    name: "main",
                    path: URL(fileURLWithPath: "/tmp/\(name)"),
                    isMainWorktree: true
                )
            ]
        )
    }

    private func request(repos: [RepoPresentationItem]) -> RepoExplorerProjectionRequest {
        RepoExplorerProjectionRequest(
            generation: repos.reduce(0) { $0 + ($1.isFavorite ? 1 : 0) },
            snapshot: RepoExplorerSnapshot(
                repos: repos,
                repoEnrichmentByRepoId: Dictionary(
                    uniqueKeysWithValues: repos.map {
                        ($0.id, resolvedRemote(repoId: $0.id, displayName: $0.name))
                    }
                ),
                groupingMode: .repo,
                query: ""
            ),
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .dataRefresh
        )
    }

    private func withFavorite(_ repo: RepoPresentationItem) -> RepoPresentationItem {
        RepoPresentationItem(
            id: repo.id,
            name: repo.name,
            repoPath: repo.repoPath,
            stableKey: repo.stableKey,
            isFavorite: true,
            note: repo.note,
            tags: repo.tags,
            worktrees: repo.worktrees
        )
    }

    private func resolvedRemote(repoId: UUID, displayName: String) -> RepoEnrichment {
        .resolvedRemote(
            repoId: repoId,
            raw: RawRepoOrigin(origin: "git@github.com:askluna/\(displayName).git", upstream: nil),
            identity: RepoIdentity(
                groupKey: "remote:askluna/\(displayName)",
                remoteSlug: "askluna/\(displayName)",
                organizationName: "askluna",
                displayName: displayName
            ),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
