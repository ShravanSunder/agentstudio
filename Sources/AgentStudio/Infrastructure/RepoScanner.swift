import AgentStudioGit
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
        func resolvedStandaloneWorkingTree(at url: URL) async -> ResolvedGitEntry?
    }

    struct AgentStudioGitRepositoryDiscoveryProvider: GitRepositoryDiscoveryProvider {
        private let client: any AgentStudioGit.AgentStudioGitLocalClient
        private let timeout: Duration

        init(
            client: any AgentStudioGit.AgentStudioGitLocalClient = AgentStudioGit.LibGit2AgentStudioGitLocalClient(),
            timeout: Duration = AppPolicies.GitRefresh.defaultSDKReadTimeout
        ) {
            self.client = client
            self.timeout = timeout
        }

        func resolvedStandaloneWorkingTree(at url: URL) async -> ResolvedGitEntry? {
            do {
                return try await Self.withTimeout(timeout) {
                    let validation = try await client.validateWorktree(
                        AgentStudioGit.GitValidateWorktreeRequest(worktreePath: url)
                    )
                    guard validation.isValid, let snapshot = validation.snapshot else { return nil }
                    let identity = try await client.repositoryIdentity(for: url)
                    return Self.resolvedEntry(
                        scannedPath: url,
                        validationSnapshot: snapshot,
                        repositoryIdentity: identity
                    )
                }
            } catch {
                return nil
            }
        }

        private static func withTimeout<ReturnValue: Sendable>(
            _ timeout: Duration,
            operation: @Sendable @escaping () async throws -> ReturnValue
        ) async throws -> ReturnValue {
            try await withThrowingTaskGroup(of: ReturnValue.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw RepoScannerDiscoveryTimeoutError.timedOut
                }

                guard let result = try await group.next() else {
                    throw RepoScannerDiscoveryTimeoutError.timedOut
                }
                group.cancelAll()
                return result
            }
        }

        private static func resolvedEntry(
            scannedPath: URL,
            validationSnapshot: AgentStudioGit.GitWorktreeSnapshot,
            repositoryIdentity: AgentStudioGit.GitRepositoryIdentity
        ) -> ResolvedGitEntry? {
            let scannedCanonicalPath = canonicalPath(scannedPath)
            let repositoryKey = validationSnapshot.repositoryID.rawValue

            guard samePath(validationSnapshot.canonicalPath, scannedCanonicalPath),
                !isSubmoduleGitDirectory(validationSnapshot.gitDirectory)
            else {
                return nil
            }

            if validationSnapshot.isMainWorktree {
                if let mainWorktreePath = repositoryIdentity.mainWorktreePath,
                    !samePath(mainWorktreePath, scannedCanonicalPath)
                {
                    return nil
                }
                return ResolvedGitEntry(
                    path: canonicalPath(validationSnapshot.canonicalPath),
                    kind: .cloneRoot,
                    repositoryKey: repositoryKey
                )
            }

            let parentClonePath =
                repositoryIdentity.mainWorktreePath
                ?? fallbackParentClonePath(repositoryID: validationSnapshot.repositoryID)
                ?? repositoryIdentity.canonicalCommonDirectory
            return ResolvedGitEntry(
                path: canonicalPath(validationSnapshot.canonicalPath),
                kind: .linkedWorktree(parentClonePath: canonicalPath(parentClonePath)),
                repositoryKey: repositoryKey
            )
        }

        private static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
            canonicalPath(lhs).path == canonicalPath(rhs).path
        }

        private static func canonicalPath(_ url: URL) -> URL {
            url.standardizedFileURL.resolvingSymlinksInPath()
        }

        private static func isSubmoduleGitDirectory(_ gitDirectory: URL) -> Bool {
            canonicalPath(gitDirectory).path.contains("/.git/modules/")
        }

        private static func fallbackParentClonePath(repositoryID: AgentStudioGit.GitRepositoryID) -> URL? {
            let commonPrefix = "common:"
            guard repositoryID.rawValue.hasPrefix(commonPrefix) else { return nil }
            let commonPath = String(repositoryID.rawValue.dropFirst(commonPrefix.count))
            guard !commonPath.isEmpty else { return nil }
            return URL(fileURLWithPath: commonPath)
        }
    }

    private enum RepoScannerDiscoveryTimeoutError: Error {
        case timedOut
    }

    /// Default scan depth for parent folder discovery.
    /// Depth 4 supports layouts like ~/projects/org/suborg/repo/.git.
    /// Scanning stops at the first .git boundary (no deeper).
    static let defaultMaxDepth = 4

    /// Scans `rootURL` for directories containing a `.git` subdirectory.
    /// Stops descending into a directory once a `.git` is found (no nested repos).
    /// Skips hidden directories and symlinks.
    func scanForGitRepos(
        in rootURL: URL,
        maxDepth: Int = Self.defaultMaxDepth,
        discoveryProvider: any GitRepositoryDiscoveryProvider = AgentStudioGitRepositoryDiscoveryProvider()
    ) async -> [URL] {
        var repos: [URL] = []
        await scanDirectory(
            Self.canonicalURL(rootURL),
            currentDepth: 0,
            maxDepth: maxDepth,
            discoveryProvider: discoveryProvider,
            results: &repos
        )
        return repos.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
                == .orderedAscending
        }
    }

    func scanForGitReposGrouped(
        in rootURL: URL,
        maxDepth: Int = Self.defaultMaxDepth,
        discoveryProvider: any GitRepositoryDiscoveryProvider = AgentStudioGitRepositoryDiscoveryProvider()
    ) async -> [RepoScanGroup] {
        var classifiedPaths: [ResolvedGitEntry] = []
        await scanDirectory(
            Self.canonicalURL(rootURL),
            currentDepth: 0,
            maxDepth: maxDepth,
            discoveryProvider: discoveryProvider,
            classifiedResults: &classifiedPaths
        )
        return Self.groupResolvedEntries(classifiedPaths)
    }

    private func scanDirectory(
        _ url: URL,
        currentDepth: Int,
        maxDepth: Int,
        discoveryProvider: any GitRepositoryDiscoveryProvider,
        results: inout [URL]
    ) async {
        guard currentDepth <= maxDepth else { return }

        let fm = FileManager.default
        // .git is always a hard boundary: classify this path, then stop.
        if Self.classifyGitEntry(at: url) != nil {
            if let resolvedEntry = await discoveryProvider.resolvedStandaloneWorkingTree(at: url) {
                results.append(resolvedEntry.path)
            }
            return
        }

        // Otherwise, scan subdirectories
        guard
            let contents = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        else { return }

        for item in contents {
            guard
                let values = try? item.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                values.isDirectory == true,
                values.isSymbolicLink != true
            else { continue }

            await scanDirectory(
                item,
                currentDepth: currentDepth + 1,
                maxDepth: maxDepth,
                discoveryProvider: discoveryProvider,
                results: &results
            )
        }
    }

    private func scanDirectory(
        _ url: URL,
        currentDepth: Int,
        maxDepth: Int,
        discoveryProvider: any GitRepositoryDiscoveryProvider,
        classifiedResults: inout [ResolvedGitEntry]
    ) async {
        guard currentDepth <= maxDepth else { return }

        let fileManager = FileManager.default
        if Self.classifyGitEntry(at: url) != nil {
            if let resolvedEntry = await discoveryProvider.resolvedStandaloneWorkingTree(at: url) {
                classifiedResults.append(resolvedEntry)
            }
            return
        }

        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        else { return }

        for item in contents {
            guard
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                values.isDirectory == true,
                values.isSymbolicLink != true
            else { continue }

            await scanDirectory(
                item,
                currentDepth: currentDepth + 1,
                maxDepth: maxDepth,
                discoveryProvider: discoveryProvider,
                classifiedResults: &classifiedResults
            )
        }
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

    private static func canonicalURL(_ url: URL) -> URL {
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
