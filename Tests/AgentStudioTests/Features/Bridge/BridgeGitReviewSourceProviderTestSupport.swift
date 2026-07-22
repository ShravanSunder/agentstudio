import AgentStudioGit
import Foundation

@testable import AgentStudio

struct GitContentLocator: Hashable, Sendable {
    let target: GitDiffTarget
    let path: String
}

actor AgentStudioGitLocalClientFake: AgentStudioGitLocalClient {
    private var diffSnapshot: GitDiffSnapshot
    private let diffFailure: GitDataPlaneError?
    private var contentByLocator: [GitContentLocator: GitContentPayload]
    private var resolvedRevisionByTarget: [GitRevisionTarget: GitResolvedRevision]
    private let contentFailureByLocator: [GitContentLocator: GitDataPlaneError]
    private let treeSnapshotByRequest: [GitTreeReadRequest: GitTreeSnapshot]
    private let treeFailure: GitDataPlaneError?
    private let statusSnapshot: GitStatusSnapshot?
    private let statusFailure: GitDataPlaneError?
    private let statusSnapshotByOptions: [GitStatusOptions: GitStatusSnapshot]
    private let statusFailureByOptions: [GitStatusOptions: GitDataPlaneError]
    private let contentReadGateByLocator: [GitContentLocator: BridgeGitContentReadGate]
    private let revisionResolutionGate: BridgeGitContentReadGate?
    private var diffRequests: [GitDiffRequest] = []
    private var contentRequests: [GitContentRequest] = []
    private var treeRequests: [GitTreeReadRequest] = []
    private var statusRequests: [(URL, GitStatusOptions)] = []
    private var revisionResolutionRequests: [GitRevisionResolutionRequest] = []

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
        statusFailureByOptions: [GitStatusOptions: GitDataPlaneError] = [:],
        resolvedRevisionByTarget: [GitRevisionTarget: GitResolvedRevision] = [:],
        contentReadGateByLocator: [GitContentLocator: BridgeGitContentReadGate] = [:],
        revisionResolutionGate: BridgeGitContentReadGate? = nil
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
        self.resolvedRevisionByTarget = resolvedRevisionByTarget
        self.contentReadGateByLocator = contentReadGateByLocator
        self.revisionResolutionGate = revisionResolutionGate
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
        revisionResolutionRequests.append(request)
        guard let revision = resolvedRevisionByTarget[request.target] else {
            throw GitDataPlaneError.unsupported(message: "missing revision")
        }
        if let revisionResolutionGate {
            await revisionResolutionGate.waitUntilReleased()
        }
        return revision
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
        if let contentReadGate = contentReadGateByLocator[locator] {
            await contentReadGate.waitUntilReleased()
        }
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

    func recordedRevisionResolutionRequests() -> [GitRevisionResolutionRequest] {
        revisionResolutionRequests
    }

    func replaceDiffSnapshot(_ snapshot: GitDiffSnapshot) {
        diffSnapshot = snapshot
    }

    func replaceContent(_ content: GitContentPayload, for locator: GitContentLocator) {
        contentByLocator[locator] = content
    }

    func replaceResolvedRevision(
        _ revision: GitResolvedRevision,
        for target: GitRevisionTarget
    ) {
        resolvedRevisionByTarget[target] = revision
    }
}

actor BridgeGitContentReadGate {
    private var didStart = false
    private var didRelease = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilReleased() async {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        guard !didRelease else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func release() {
        didRelease = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }
}
