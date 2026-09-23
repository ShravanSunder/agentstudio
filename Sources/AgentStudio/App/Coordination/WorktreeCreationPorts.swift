import AgentStudioCore
import AgentStudioGit
import Foundation

/// The two SDK reads/writes worktree creation needs, narrowed so the coordinator can be
/// proven with a fake and the production path stays the SDK's serial writer lane.
protocol WorktreeCreationGitClient: Sendable {
    /// The commit the source worktree has checked out; new branches start here.
    func headCommit(ofWorktreeAt worktreePath: URL) async throws(GitDataPlaneError) -> String
    func createWorktree(_ request: GitCreateWorktreeRequest) async throws(GitDataPlaneError) -> GitWorktreeSnapshot
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

    func headCommit(ofWorktreeAt worktreePath: URL) async throws(GitDataPlaneError) -> String {
        let validation = try await client.validateWorktree(GitValidateWorktreeRequest(worktreePath: worktreePath))
        guard validation.isValid, let headCommit = validation.snapshot?.head?.oid else {
            throw GitDataPlaneError.headUnavailable
        }
        return headCommit
    }

    func createWorktree(_ request: GitCreateWorktreeRequest) async throws(GitDataPlaneError) -> GitWorktreeSnapshot {
        try await client.createWorktree(request)
    }
}
