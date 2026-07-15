import Foundation

/// Scans a directory tree for git repositories up to a configurable depth.
struct RepoScanner {
    enum GitEntryKind: Sendable, Equatable {
        case cloneRoot
        case linkedWorktree(parentClonePath: URL)
    }

    struct RepoScanGroup: Sendable, Equatable {
        let clonePath: URL
        let linkedWorktreePaths: [URL]
    }

    struct ResolvedGitEntry: Sendable, Equatable {
        let path: URL
        let kind: GitEntryKind
        let repositoryKey: String
    }

    protocol GitRepositoryDiscoveryProvider: Sendable {
        func discoveryOutcome(for url: URL) async -> GitRepositoryDiscoveryOutcome
    }

    /// Default scan depth for parent folder discovery.
    /// Depth 4 supports layouts like ~/projects/org/suborg/repo/.git.
    /// Scanning stops at the first .git boundary (no deeper).
    static let defaultMaxDepth = 4

    func scan(
        in rootURL: URL,
        maxDepth: Int = Self.defaultMaxDepth,
        discoveryProvider: any GitRepositoryDiscoveryProvider = AgentStudioGitRepositoryDiscoveryProvider()
    ) async -> RepoScannerResult {
        let session = makeSession(
            in: rootURL,
            maxDepth: maxDepth
        )
        while true {
            switch await session.advanceOneQuantum() {
            case .suspended:
                continue
            case .validationRequired(let request):
                let validationClock = ContinuousClock()
                let validationStartedAt = validationClock.now
                let discoveryOutcome: GitRepositoryDiscoveryOutcome
                if Task.isCancelled {
                    discoveryOutcome = .cancelled
                } else {
                    discoveryOutcome = await discoveryProvider.discoveryOutcome(
                        for: request.candidateURL
                    )
                }
                let consumption = session.consumeValidationCompletion(
                    RepoScannerValidationCompletion(
                        request: request,
                        outcome: discoveryOutcome,
                        validationServiceDuration: validationStartedAt.duration(
                            to: validationClock.now
                        )
                    )
                )
                guard consumption == .consumed else {
                    _ = session.cancel()
                    continue
                }
            case .finished(let result):
                return result
            }
        }
    }

    /// Scans `rootURL` for directories containing a `.git` subdirectory.
    /// Stops descending into a directory once a `.git` is found (no nested repos).
    /// Skips hidden directories and symlinks.
    func scanForGitRepos(
        in rootURL: URL,
        maxDepth: Int = Self.defaultMaxDepth,
        discoveryProvider: any GitRepositoryDiscoveryProvider = AgentStudioGitRepositoryDiscoveryProvider()
    ) async -> [URL] {
        switch await scan(in: rootURL, maxDepth: maxDepth, discoveryProvider: discoveryProvider) {
        case .completeAuthoritative(let completeScan):
            return completeScan.verifiedEntries.map(\.path)
        case .partial(let partialScan):
            return partialScan.verifiedEntries.map(\.path)
        case .cancelled(let cancelledScan):
            return cancelledScan.verifiedEntries.map(\.path)
        case .unavailable, .failed:
            return []
        }
    }

    func scanForGitReposGrouped(
        in rootURL: URL,
        maxDepth: Int = Self.defaultMaxDepth,
        discoveryProvider: any GitRepositoryDiscoveryProvider = AgentStudioGitRepositoryDiscoveryProvider()
    ) async -> [RepoScanGroup] {
        let verifiedEntries: [ResolvedGitEntry]
        switch await scan(in: rootURL, maxDepth: maxDepth, discoveryProvider: discoveryProvider) {
        case .completeAuthoritative(let completeScan):
            verifiedEntries = completeScan.verifiedEntries
        case .partial(let partialScan):
            verifiedEntries = partialScan.verifiedEntries
        case .cancelled(let cancelledScan):
            verifiedEntries = cancelledScan.verifiedEntries
        case .unavailable, .failed:
            verifiedEntries = []
        }
        return Self.groupResolvedEntries(verifiedEntries)
    }

    static func classifyGitEntry(at url: URL) -> GitEntryKind? {
        let gitMarkerPath = url.appending(path: ".git")
        guard FileManager.default.fileExists(atPath: gitMarkerPath.path) else { return nil }

        guard let values = try? gitMarkerPath.resourceValues(forKeys: [.isDirectoryKey]),
            let isDirectory = values.isDirectory
        else {
            // .git exists but can't stat — treat as clone root boundary so scanner stops descending
            return .cloneRoot
        }

        if isDirectory {
            return .cloneRoot
        }

        guard
            let gitFileContents = try? String(contentsOf: gitMarkerPath, encoding: .utf8),
            let parentClonePath = parseParentClonePath(
                fromGitFileContent: gitFileContents,
                relativeTo: url
            )
        else {
            // .git file exists but unreadable or unparseable — treat as clone root boundary
            return .cloneRoot
        }

        return .linkedWorktree(parentClonePath: parentClonePath)
    }

    static func parseParentClonePath(fromGitFileContent gitFileContent: String) -> URL? {
        parseParentClonePath(fromGitFileContent: gitFileContent, relativeTo: nil)
    }

    static func groupClassifiedPaths(_ classifiedPaths: [(URL, GitEntryKind)]) -> [RepoScanGroup] {
        var clonePathByKey: [String: URL] = [:]
        var groupedByClonePathKey: [String: [URL]] = [:]

        for (path, kind) in classifiedPaths {
            switch kind {
            case .cloneRoot:
                let clonePath = canonicalURL(path)
                let cloneKey = canonicalPathKey(clonePath)
                clonePathByKey[cloneKey] = clonePath
                if groupedByClonePathKey[cloneKey] == nil {
                    groupedByClonePathKey[cloneKey] = []
                }
            case .linkedWorktree(let parentClonePath):
                let clonePath = canonicalURL(parentClonePath)
                let cloneKey = canonicalPathKey(clonePath)
                clonePathByKey[cloneKey] = clonePath
                groupedByClonePathKey[cloneKey, default: []]
                    .append(canonicalURL(path))
            }
        }

        return
            groupedByClonePathKey
            .compactMap { clonePathKey, linkedWorktreePaths in
                guard let clonePath = clonePathByKey[clonePathKey] else { return nil }
                return RepoScanGroup(
                    clonePath: clonePath,
                    linkedWorktreePaths: linkedWorktreePaths.sorted {
                        $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
                            == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.clonePath.lastPathComponent.localizedCaseInsensitiveCompare($1.clonePath.lastPathComponent)
                    == .orderedAscending
            }
    }

    static func groupResolvedEntries(_ resolvedEntries: [ResolvedGitEntry]) -> [RepoScanGroup] {
        var clonePathByKey: [String: URL] = [:]
        var groupedByClonePathKey: [String: [URL]] = [:]

        for entry in resolvedEntries {
            switch entry.kind {
            case .cloneRoot:
                clonePathByKey[entry.repositoryKey] = canonicalURL(entry.path)
                if groupedByClonePathKey[entry.repositoryKey] == nil {
                    groupedByClonePathKey[entry.repositoryKey] = []
                }
            case .linkedWorktree(let parentClonePath):
                if clonePathByKey[entry.repositoryKey] == nil {
                    clonePathByKey[entry.repositoryKey] = canonicalURL(parentClonePath)
                }
                groupedByClonePathKey[entry.repositoryKey, default: []]
                    .append(canonicalURL(entry.path))
            }
        }

        return
            groupedByClonePathKey
            .compactMap { clonePathKey, linkedWorktreePaths in
                guard let clonePath = clonePathByKey[clonePathKey] else { return nil }
                return RepoScanGroup(
                    clonePath: clonePath,
                    linkedWorktreePaths: linkedWorktreePaths.sorted {
                        $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
                            == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.clonePath.lastPathComponent.localizedCaseInsensitiveCompare($1.clonePath.lastPathComponent)
                    == .orderedAscending
            }
    }

    static func canonicalURL(_ url: URL) -> URL {
        URL(fileURLWithPath: canonicalPathKey(url))
    }

    private static func canonicalPathKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func parseParentClonePath(
        fromGitFileContent gitFileContent: String,
        relativeTo worktreeURL: URL?
    ) -> URL? {
        guard
            let gitDirURL = parseGitDirectoryPath(
                fromGitFileContent: gitFileContent,
                relativeTo: worktreeURL
            )
        else { return nil }

        let gitDirPath = gitDirURL.standardizedFileURL.path
        guard let worktreeRange = gitDirPath.range(of: "/.git/worktrees/", options: .backwards) else {
            return nil
        }
        return URL(fileURLWithPath: String(gitDirPath[..<worktreeRange.lowerBound])).standardizedFileURL
    }

    private static func parseGitDirectoryPath(
        fromGitFileContent gitFileContent: String,
        relativeTo worktreeURL: URL?
    ) -> URL? {
        let trimmedContent = gitFileContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.hasPrefix("gitdir:") else { return nil }

        let gitDirPathString =
            trimmedContent
            .dropFirst("gitdir:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if gitDirPathString.hasPrefix("/") {
            return URL(fileURLWithPath: gitDirPathString).standardizedFileURL
        }
        guard let worktreeURL else { return nil }
        return worktreeURL.appending(path: gitDirPathString).standardizedFileURL
    }
}

extension RepoScanner {
    func makeSession(
        in rootURL: URL,
        maxDepth: Int = Self.defaultMaxDepth,
        quantumBudget: RepoScannerQuantumBudget = .productionDefault,
        capacity: RepoScannerSessionCapacity = .productionDefault
    ) -> RepoScannerSessionPort {
        let storage = RepoScannerTraversalSession(
            rootURL: Self.canonicalURL(rootURL),
            maxDepth: maxDepth,
            quantumBudget: quantumBudget,
            capacity: capacity
        )
        return RepoScannerSessionPort(
            id: storage.id,
            advanceOperation: storage.advanceOneQuantum,
            validationCompletionOperation: storage.consumeValidationCompletion,
            cancellationOperation: storage.cancel
        )
    }
}

struct RepoScannerSessionPort: Sendable {
    let id: RepoScannerSessionID

    private let advanceOperation: @Sendable () async -> RepoScannerQuantumOutcome
    private let validationCompletionOperation:
        @Sendable (RepoScannerValidationCompletion) -> RepoScannerValidationCompletionConsumptionResult
    private let cancellationOperation: @Sendable () -> RepoScannerSessionCancellationResult

    fileprivate init(
        id: RepoScannerSessionID,
        advanceOperation: @escaping @Sendable () async -> RepoScannerQuantumOutcome,
        validationCompletionOperation:
            @escaping @Sendable (RepoScannerValidationCompletion) ->
            RepoScannerValidationCompletionConsumptionResult,
        cancellationOperation: @escaping @Sendable () -> RepoScannerSessionCancellationResult
    ) {
        self.id = id
        self.advanceOperation = advanceOperation
        self.validationCompletionOperation = validationCompletionOperation
        self.cancellationOperation = cancellationOperation
    }

    func advanceOneQuantum() async -> RepoScannerQuantumOutcome {
        await advanceOperation()
    }

    func consumeValidationCompletion(
        _ completion: RepoScannerValidationCompletion
    ) -> RepoScannerValidationCompletionConsumptionResult {
        validationCompletionOperation(completion)
    }

    func cancel() -> RepoScannerSessionCancellationResult {
        cancellationOperation()
    }
}
