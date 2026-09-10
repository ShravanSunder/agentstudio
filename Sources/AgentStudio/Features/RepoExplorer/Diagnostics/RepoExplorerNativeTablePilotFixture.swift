import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Foundation

@MainActor
final class PilotFixture {
    let contentChild: PilotContentChild

    private let repos: [RepoPresentationItem]
    private let repoEnrichmentByRepoID: [UUID: RepoEnrichment]
    private let paneLocationsByWorktreeID: [UUID: [WorkspacePaneLocation]]
    private let worktreeEnrichmentByID: [UUID: WorktreeEnrichment]
    private let favoriteTargetRepositoryID: UUID

    init(
        topology: PilotTopology,
        representedRowCount: Int
    ) {
        repos = topology.repos
        repoEnrichmentByRepoID = topology.repoEnrichmentByRepoID
        paneLocationsByWorktreeID = topology.paneLocationsByWorktreeID
        worktreeEnrichmentByID = topology.worktreeEnrichmentByID
        favoriteTargetRepositoryID = topology.repos.last?.id ?? UUIDv7.generate()
        contentChild = PilotContentChild(representedRowCount: representedRowCount)
    }

    func request(generation: Int, favoriteTarget: Bool) -> RepoExplorerProjectionRequest {
        RepoExplorerProjectionRequest(
            generation: generation,
            snapshot: RepoExplorerSnapshot(
                repos: repos.map { repo in
                    guard repo.id == favoriteTargetRepositoryID else { return repo }
                    return RepoPresentationItem(
                        id: repo.id,
                        name: repo.name,
                        repoPath: repo.repoPath,
                        stableKey: repo.stableKey,
                        isFavorite: favoriteTarget,
                        note: repo.note,
                        tags: repo.tags,
                        worktrees: repo.worktrees,
                        worktreeStableKeysByID: repo.worktreeStableKeysByID
                    )
                },
                repoEnrichmentByRepoId: repoEnrichmentByRepoID,
                groupingMode: .repo,
                query: "",
                paneLocationsByWorktreeId: paneLocationsByWorktreeID
            ),
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .startupDiagnostic,
            worktreeEnrichmentSnapshot: worktreeEnrichmentByID
        )
    }

    func detach() {
        contentChild.detach()
    }
}

struct PilotTopology {
    let repos: [RepoPresentationItem]
    let repoEnrichmentByRepoID: [UUID: RepoEnrichment]
    let paneLocationsByWorktreeID: [UUID: [WorkspacePaneLocation]]
    let worktreeEnrichmentByID: [UUID: WorktreeEnrichment]

    @concurrent nonisolated static func build(
        repositoryCount: Int,
        worktreeCount: Int,
        tabCount: Int,
        paneCount: Int
    ) async -> Self {
        precondition(repositoryCount > 0 && worktreeCount >= repositoryCount)
        precondition(tabCount > 0 && paneCount >= tabCount)

        var worktreesByRepositoryIndex = Array(
            repeating: [Worktree](),
            count: repositoryCount
        )
        var worktreeStableKeysByRepositoryIndex = Array(
            repeating: [UUID: String](),
            count: repositoryCount
        )
        let repositoryIDs = (0..<repositoryCount).map { _ in UUIDv7.generate() }
        var allWorktrees: [Worktree] = []
        allWorktrees.reserveCapacity(worktreeCount)

        for worktreeIndex in 0..<worktreeCount {
            let repositoryIndex = worktreeIndex % repositoryCount
            let repositoryID = repositoryIDs[repositoryIndex]
            let worktreeID = UUIDv7.generate()
            let isMainWorktree = worktreeIndex < repositoryCount
            let stableKey = "pilot-worktree-\(worktreeIndex)"
            let worktree = Worktree(
                id: worktreeID,
                repoId: repositoryID,
                name: isMainWorktree ? "main" : "linked-\(worktreeIndex)",
                path: URL(fileURLWithPath: "/pilot/repo-\(repositoryIndex)/\(stableKey)"),
                isMainWorktree: isMainWorktree
            )
            worktreesByRepositoryIndex[repositoryIndex].append(worktree)
            worktreeStableKeysByRepositoryIndex[repositoryIndex][worktreeID] = stableKey
            allWorktrees.append(worktree)
        }

        let repos = (0..<repositoryCount).map { repositoryIndex in
            let repositoryID = repositoryIDs[repositoryIndex]
            return RepoPresentationItem(
                id: repositoryID,
                name: String(format: "repo-%03d", repositoryIndex),
                repoPath: URL(fileURLWithPath: "/pilot/repo-\(repositoryIndex)"),
                stableKey: "pilot-repo-\(repositoryIndex)",
                worktrees: worktreesByRepositoryIndex[repositoryIndex],
                worktreeStableKeysByID: worktreeStableKeysByRepositoryIndex[repositoryIndex]
            )
        }
        let repoEnrichmentByRepoID = Dictionary(
            uniqueKeysWithValues: repos.enumerated().map { repositoryIndex, repo in
                (
                    repo.id,
                    RepoEnrichment.resolvedRemote(
                        repoId: repo.id,
                        raw: RawRepoOrigin(
                            origin: "git@example.invalid:pilot/repo-\(repositoryIndex).git",
                            upstream: nil
                        ),
                        identity: RepoIdentity(
                            groupKey: "remote:pilot/repo-\(repositoryIndex)",
                            remoteSlug: "pilot/repo-\(repositoryIndex)",
                            organizationName: "pilot",
                            displayName: repo.name
                        ),
                        updatedAt: Date(timeIntervalSince1970: 0)
                    )
                )
            })
        let worktreeEnrichmentByID = Dictionary(
            uniqueKeysWithValues: allWorktrees.map { worktree in
                (
                    worktree.id,
                    WorktreeEnrichment(
                        worktreeId: worktree.id,
                        repoId: worktree.repoId,
                        branch: "main",
                        isMainWorktree: worktree.isMainWorktree,
                        updatedAt: Date(timeIntervalSince1970: 0)
                    )
                )
            })
        let tabIDs = (0..<tabCount).map { _ in UUIDv7.generate() }
        var paneLocationsByWorktreeID: [UUID: [WorkspacePaneLocation]] = [:]
        for paneIndex in 0..<paneCount {
            let worktree = allWorktrees[paneIndex % allWorktrees.count]
            let tabIndex = paneIndex % tabCount
            paneLocationsByWorktreeID[worktree.id, default: []].append(
                WorkspacePaneLocation(
                    paneId: UUIDv7.generate(),
                    tabId: tabIDs[tabIndex],
                    tabIndex: tabIndex,
                    paneIndexInTab: paneIndex / tabCount,
                    isActiveInTab: paneIndex < tabCount
                )
            )
        }
        return Self(
            repos: repos,
            repoEnrichmentByRepoID: repoEnrichmentByRepoID,
            paneLocationsByWorktreeID: paneLocationsByWorktreeID,
            worktreeEnrichmentByID: worktreeEnrichmentByID
        )
    }
}

@MainActor
final class PilotContentChild: NSObject, RepoExplorerMaterializationContentChild,
    NSTableViewDataSource
{
    let view: NSView
    private(set) var isExact = true
    private(set) var failureReason: RepoExplorerNativeTablePilotResult.FailureReason?

    private let representedRowCount: Int
    private let tableView = NSTableView()
    private let scrollView: NSScrollView
    private var snapshot: RepoExplorerMaterializationSnapshot?
    private var measurementMilliseconds: [Double] = []

    init(representedRowCount: Int) {
        self.representedRowCount = representedRowCount
        let rowHeight = PilotLayout.rowHeight
        let viewportHeight = rowHeight * CGFloat(representedRowCount)
        scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 320, height: viewportHeight)
        )
        view = scrollView
        super.init()
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = .zero
        tableView.headerView = nil
        tableView.addTableColumn(
            NSTableColumn(identifier: NSUserInterfaceItemIdentifier("repo-explorer-pilot"))
        )
        tableView.dataSource = self
        scrollView.hasVerticalScroller = false
        scrollView.documentView = tableView
        updateTableFrame(rowCount: 0)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        snapshot?.rows.count ?? 0
    }

    func tableView(
        _ tableView: NSTableView,
        objectValueFor tableColumn: NSTableColumn?,
        row: Int
    ) -> Any? {
        row
    }

    func apply(
        _ candidate: RepoExplorerMaterializationContentCandidate,
        completion: @escaping (RepoExplorerMaterializationChildDisposition) -> Void
    ) {
        snapshot = candidate.snapshot
        updateTableFrame(rowCount: candidate.snapshot.rows.count)
        let start = ContinuousClock.now
        let applied = RepoExplorerNativeTransactionApplier.apply(
            tablePlan: candidate.tableUpdatePlan,
            to: tableView
        )
        let elapsed = start.duration(to: ContinuousClock.now)
        measurementMilliseconds.append(Self.milliseconds(elapsed))
        scrollView.layoutSubtreeIfNeeded()
        tableView.layoutSubtreeIfNeeded()
        let visibleRowCount = tableView.rows(
            in: scrollView.contentView.documentVisibleRect
        ).length
        if !applied || tableView.numberOfRows != candidate.snapshot.rows.count {
            failureReason = .transactionInvalid
        } else if visibleRowCount != min(representedRowCount, candidate.snapshot.rows.count) {
            failureReason = .fixtureInvalid
        }
        isExact = failureReason == nil
        completion(isExact ? .accepted : .rejected)
    }

    func prepareForRemoval(
        visibleGeneration: UInt64,
        completion: @escaping (RepoExplorerMaterializationChildDisposition) -> Void
    ) {
        completion(.accepted)
    }

    func suspendDemand() {}

    func resumeDemand(visibleGeneration: UInt64) {
        _ = visibleGeneration
    }

    func detach() {
        tableView.dataSource = nil
        scrollView.documentView = nil
        snapshot = nil
        measurementMilliseconds.removeAll(keepingCapacity: false)
    }

    func discardMeasurements() {
        measurementMilliseconds.removeAll(keepingCapacity: true)
    }

    func takeLastMeasurement() -> Double? {
        guard let measurement = measurementMilliseconds.last else { return nil }
        measurementMilliseconds.removeLast()
        return measurement
    }

    private func updateTableFrame(rowCount: Int) {
        let documentHeight = max(
            scrollView.contentView.bounds.height,
            CGFloat(rowCount) * tableView.rowHeight
        )
        tableView.frame = NSRect(
            x: 0,
            y: 0,
            width: scrollView.contentView.bounds.width,
            height: documentHeight
        )
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1e3
            + Double(components.attoseconds) / 1e15
    }
}
