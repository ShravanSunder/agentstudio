import AgentStudioCore
import AgentStudioGit
import Foundation

/// The SDK reads and writes worktree creation needs, narrowed so the coordinator can be
/// proven with a fake and the production path stays the SDK's serial writer lane.
protocol WorktreeCreationGitClient: Sendable {
    func createWorktree(_ request: GitCreateWorktreeRequest) async throws(GitDataPlaneError) -> GitWorktreeSnapshot
    /// Copy-on-write fork of the source's current files at its captured HEAD.
    func forkWorktree(_ request: GitForkWorktreeRequest) async throws(GitWorktreeForkError) -> GitForkWorktreeResult
}

/// Keeps a destination out of watched-folder publication while it is being built, then
/// rescans the one watched folder that owns it.
protocol WorktreePublicationHolding: AnyObject, Sendable {
    func holdPublication(of destination: URL) async -> WatchedFolderPublicationHoldID
    func releasePublicationHold(_ holdID: WatchedFolderPublicationHoldID) async
    /// Returns after the rescan result for `watchedPathID` has been applied and posted.
    func refreshWatchedFolder(_ watchedPathID: UUID, among watchedPaths: [WatchedPath]) async
}

struct LibGit2WorktreeCreationGitClient: WorktreeCreationGitClient {
    private let client: any AgentStudioGitLocalClient

    init(client: any AgentStudioGitLocalClient = LibGit2AgentStudioGitLocalClient()) {
        self.client = client
    }

    func createWorktree(_ request: GitCreateWorktreeRequest) async throws(GitDataPlaneError) -> GitWorktreeSnapshot {
        try await client.createWorktree(request)
    }

    func forkWorktree(_ request: GitForkWorktreeRequest) async throws(GitWorktreeForkError) -> GitForkWorktreeResult {
        try await client.forkWorktree(request)
    }
}

/// Uses the SDK's origin/HEAD resolution, then local main/master branch facts.
struct SDKWorktreeDefaultStartPointResolver: WorktreeDefaultStartPointResolving {
    private let client: any AgentStudioGitLocalClient

    init(client: any AgentStudioGitLocalClient = LibGit2AgentStudioGitLocalClient()) {
        self.client = client
    }

    @concurrent
    func resolveDefaultStartPoint(repositoryPath: URL) async throws(GitDataPlaneError) -> WorktreeDefaultStartPoint {
        if let originHead = try await client.resolveReviewDefaultTarget(for: repositoryPath),
            case .remoteTracking(let remoteName, _, _) = originHead,
            remoteName == "origin"
        {
            return .resolved(displayRef: originHead.displayName, startPoint: originHead.referenceName)
        }
        let branches = try await client.branches(for: repositoryPath)
        for branchName in ["main", "master"] where branches.contains(where: { $0.name == branchName }) {
            return .resolved(displayRef: branchName, startPoint: "refs/heads/\(branchName)")
        }
        return .noDefaultBranch
    }
}

/// Live fork-eligibility port over the SDK's read-only `forkWorktreeEligibility` query:
/// host, volume, and File Provider facts only. The app never re-implements those rules;
/// it turns the SDK's reason into row copy, and `forkWorktree`'s own preflight rejection
/// stays authoritative after `.available`.
struct SDKWorktreeForkEligibilityChecker: WorktreeForkEligibilityChecking {
    typealias EligibilityQuery =
        @Sendable (_ sourceWorktreePath: URL, _ destinationPath: URL) async -> GitWorktreeForkEligibility

    /// The branch name is not typed yet when the source is chosen, so the query names a
    /// placeholder leaf in the directory every sibling destination shares.
    static let destinationProbeName = "agentstudio-fork-eligibility-probe"

    private let query: EligibilityQuery

    init(
        query: @escaping EligibilityQuery = { sourceWorktreePath, destinationPath in
            await LibGit2AgentStudioGitLocalClient().forkWorktreeEligibility(
                sourceWorktreePath: sourceWorktreePath,
                destinationPath: destinationPath
            )
        }
    ) {
        self.query = query
    }

    @concurrent
    func forkEligibility(sourceWorktreePath: URL, destinationDirectory: URL) async -> WorktreeForkEligibility {
        let destinationPath = destinationDirectory.appending(
            path: Self.destinationProbeName, directoryHint: .isDirectory)
        switch await query(sourceWorktreePath, destinationPath) {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: WorktreeForkRejectionCopy.phrase(for: reason))
        }
    }
}
