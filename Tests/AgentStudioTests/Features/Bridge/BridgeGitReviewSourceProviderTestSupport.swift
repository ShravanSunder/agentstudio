import AgentStudioGit
import Foundation

@testable import AgentStudio

struct GitContentLocator: Hashable, Sendable {
    let target: GitDiffTarget
    let path: String
}

actor AgentStudioGitLocalClientFake: AgentStudioGitLocalClient {
    private let diffSnapshot: GitDiffSnapshot
    private let diffFailure: GitDataPlaneError?
    private let contentByLocator: [GitContentLocator: GitContentPayload]
    private let contentFailureByLocator: [GitContentLocator: GitDataPlaneError]
    private let treeSnapshotByRequest: [GitTreeReadRequest: GitTreeSnapshot]
    private let treeFailure: GitDataPlaneError?
    private let statusSnapshot: GitStatusSnapshot?
    private let statusFailure: GitDataPlaneError?
    private let statusSnapshotByOptions: [GitStatusOptions: GitStatusSnapshot]
    private let statusFailureByOptions: [GitStatusOptions: GitDataPlaneError]
    private var diffRequests: [GitDiffRequest] = []
    private var contentRequests: [GitContentRequest] = []
    private var treeRequests: [GitTreeReadRequest] = []
    private var statusRequests: [(URL, GitStatusOptions)] = []

    init(
        diffSnapshot: GitDiffSnapshot = GitDiffSnapshot(files: []),
        diffFailure: GitDataPlaneError? = nil,
        contentByLocator: [GitContentLocator: GitContentPayload] = [:],
        contentFailureByLocator: [GitContentLocator: GitDataPlaneError] = [:],
        treeSnapshotByRequest: [GitTreeReadRequest: GitTreeSnapshot] = [:],
        treeFailure: GitDataPlaneError? = nil,
        statusSnapshot: GitStatusSnapshot? = nil,
        statusFailure: GitDataPlaneError? = nil,
        statusSnapshotByOptions: [GitStatusOptions: GitStatusSnapshot] = [:],
        statusFailureByOptions: [GitStatusOptions: GitDataPlaneError] = [:]
    ) {
        self.diffSnapshot = diffSnapshot
        self.diffFailure = diffFailure
        self.contentByLocator = contentByLocator
        self.contentFailureByLocator = contentFailureByLocator
        self.treeSnapshotByRequest = treeSnapshotByRequest
        self.treeFailure = treeFailure
        self.statusSnapshot = statusSnapshot
        self.statusFailure = statusFailure
        self.statusSnapshotByOptions = statusSnapshotByOptions
        self.statusFailureByOptions = statusFailureByOptions
    }

    func repositoryIdentity(for worktreePath: URL) async throws(GitDataPlaneError) -> GitRepositoryIdentity {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func worktrees(for repositoryPath: URL) async throws(GitDataPlaneError) -> [GitWorktreeSnapshot] {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func validateWorktree(_ request: GitValidateWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeValidation
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func createWorktree(_ request: GitCreateWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeSnapshot
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func pruneStaleWorktree(_ request: GitPruneStaleWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreePruneResult
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func removeWorktree(_ request: GitRemoveWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeRemovalResult
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func lockWorktree(_ request: GitLockWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeSnapshot
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func unlockWorktree(_ request: GitUnlockWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeSnapshot
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func status(for worktreePath: URL, options: GitStatusOptions) async throws(GitDataPlaneError)
        -> GitStatusSnapshot
    {
        statusRequests.append((worktreePath, options))
        if let optionFailure = statusFailureByOptions[options] {
            throw optionFailure
        }
        if let optionSnapshot = statusSnapshotByOptions[options] {
            return optionSnapshot
        }
        if let statusFailure {
            throw statusFailure
        }
        guard let statusSnapshot else {
            throw GitDataPlaneError.unsupported(message: "not used")
        }
        return statusSnapshot
    }

    func branches(for repositoryPath: URL) async throws(GitDataPlaneError) -> [GitBranchSnapshot] {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func resolveRevision(_ request: GitRevisionResolutionRequest) async throws(GitDataPlaneError)
        -> GitResolvedRevision
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func trackedPaths(
        for worktreePath: URL,
        options: GitTrackedPathsOptions
    ) async throws(GitDataPlaneError) -> GitTrackedPathsSnapshot {
        GitTrackedPathsSnapshot(entries: [], rawIndexEntryCount: 0)
    }

    func isPathIgnored(
        repositoryAt worktreePath: URL,
        relativePath: String
    ) async throws(GitDataPlaneError) -> Bool {
        false
    }

    func ignoredPaths(
        repositoryAt worktreePath: URL,
        relativePaths: [String]
    ) async throws(GitDataPlaneError) -> [GitIgnoreCheck] {
        relativePaths.map { GitIgnoreCheck(relativePath: $0, isIgnored: false) }
    }

    func readTree(_ request: GitTreeReadRequest) async throws(GitDataPlaneError) -> GitTreeSnapshot {
        treeRequests.append(request)
        if let treeFailure {
            throw treeFailure
        }
        guard let treeSnapshot = treeSnapshotByRequest[request] else {
            throw GitDataPlaneError.unsupported(message: "missing tree for \(request.path ?? "<root>")")
        }
        return treeSnapshot
    }

    func diff(_ request: GitDiffRequest) async throws(GitDataPlaneError) -> GitDiffSnapshot {
        diffRequests.append(request)
        if let diffFailure {
            throw diffFailure
        }
        return diffSnapshot
    }

    func content(_ request: GitContentRequest) async throws(GitDataPlaneError) -> GitContentPayload {
        contentRequests.append(request)
        let locator = GitContentLocator(target: request.target, path: request.path)
        if let failure = contentFailureByLocator[locator] {
            throw failure
        }
        guard let content = contentByLocator[locator] else {
            throw GitDataPlaneError.unsupported(message: "missing content for \(request.path)")
        }
        return content
    }

    func recordedDiffRequests() -> [GitDiffRequest] {
        diffRequests
    }

    func recordedContentRequests() -> [GitContentRequest] {
        contentRequests
    }

    func recordedTreeRequests() -> [GitTreeReadRequest] {
        treeRequests
    }

    func recordedStatusRequestsCount() -> Int {
        statusRequests.count
    }

    func recordedStatusOptions() -> [GitStatusOptions] {
        statusRequests.map(\.1)
    }
}
