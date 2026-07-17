import AgentStudioGit
import Foundation

typealias BridgeWorktreeTrackedFilePathsLoader = @Sendable (URL) async throws -> Set<String>

struct BridgeWorktreeFileIgnorePolicy: Sendable {
    static let empty = Self(
        filesystemPathFilter: FilesystemPathFilter.empty,
        publishableFilePaths: nil,
        trackedPathsAndAncestors: []
    )

    private let filesystemPathFilter: FilesystemPathFilter

    /// Git-truth publishable manifest computed at open: tracked index paths
    /// (excluding submodules) plus untracked-not-ignored status entries,
    /// minus worktree deletions and rename sources. Neither input ever
    /// materializes the ignored universe — `trackedPaths` reads the index
    /// and `status(includeIgnored: false)` prunes ignored directories at
    /// their boundary. `nil` means the root is not a git worktree and
    /// enumeration falls back to the filesystem walk.
    let publishableFilePaths: Set<String>?
    private let trackedPathsAndAncestors: Set<String>

    init(
        filesystemPathFilter: FilesystemPathFilter,
        publishableFilePaths: Set<String>?,
        trackedPathsAndAncestors: Set<String> = []
    ) {
        self.filesystemPathFilter = filesystemPathFilter
        self.publishableFilePaths = publishableFilePaths
        self.trackedPathsAndAncestors = trackedPathsAndAncestors
    }

    static func load(
        rootURL: URL,
        gitReadContext: BridgeGitReadContext,
        statusProvider: any GitWorkingTreeStatusProvider = AgentStudioGitWorkingTreeStatusProvider(),
        trackedFilePathsTimeout: Duration = AppPolicies.Bridge.worktreeFileManifestStatusReadTimeout,
        trackedFilePathsLoader: @escaping BridgeWorktreeTrackedFilePathsLoader = loadTrackedFilePaths
    ) async -> Self {
        async let filesystemPathFilter = FilesystemPathFilter.loadOffExecutor(forRootPath: rootURL)
        async let trackedFilePathsTask = boundedTrackedFilePaths(
            rootURL: rootURL,
            gitReadContext: gitReadContext,
            timeout: trackedFilePathsTimeout,
            loader: trackedFilePathsLoader
        )
        async let statusResult = statusProvider.statusResult(for: rootURL)
        let trackedFilePaths = await trackedFilePathsTask
        let publishableFilePaths = await publishableFilePaths(
            rootURL: rootURL,
            trackedFilePaths: trackedFilePaths,
            statusResult: statusResult
        )
        return await Self(
            filesystemPathFilter: filesystemPathFilter,
            publishableFilePaths: publishableFilePaths,
            trackedPathsAndAncestors: trackedPathsAndAncestors(trackedFilePaths ?? [])
        )
    }

    func isIgnored(relativePath: String) -> Bool {
        let normalizedPath = Self.normalized(relativePath)
        guard !normalizedPath.isEmpty, normalizedPath != "." else {
            return false
        }
        // A path in the publishable manifest is git-truth published; only
        // paths outside it (new files, directories) fall back to the root
        // gitignore rules.
        if let publishableFilePaths, publishableFilePaths.contains(normalizedPath) {
            return false
        }
        if trackedPathsAndAncestors.contains(normalizedPath) {
            return false
        }
        return filesystemPathFilter.isIgnored(relativePath: normalizedPath)
    }

    @concurrent nonisolated static func loadTrackedFilePaths(rootURL: URL) async throws -> Set<String> {
        let client = LibGit2AgentStudioGitLocalClient()
        let trackedSnapshot = try await client.trackedPaths(
            for: rootURL,
            options: GitTrackedPathsOptions()
        )
        return Set(trackedSnapshot.entries.map { normalized($0.path) }.filter { !$0.isEmpty })
    }

    @concurrent nonisolated private static func boundedTrackedFilePaths(
        rootURL: URL,
        gitReadContext: BridgeGitReadContext,
        timeout: Duration,
        loader: @escaping BridgeWorktreeTrackedFilePathsLoader
    ) async -> Set<String>? {
        do {
            return try await gitReadContext.scheduler.read(
                request: BridgeGitReadRequest(
                    worktreeKey: gitReadContext.worktreeKey,
                    operationClass: .reviewMetadata,
                    coalescingKey: BridgeGitReadCoalescingKey(token: "tracked-paths-default"),
                    freshnessKey: BridgeGitReadFreshnessKey(token: UUID().uuidString),
                    deadline: timeout
                ),
                operation: { try await loader(rootURL) }
            )
        } catch {
            return nil
        }
    }

    private static func publishableFilePaths(
        rootURL: URL,
        trackedFilePaths: Set<String>?,
        statusResult: GitWorkingTreeStatusResult
    ) -> Set<String>? {
        guard let trackedFilePaths, case .available(let status) = statusResult else { return nil }
        var publishablePaths = Set(
            trackedFilePaths.filter { FileManager.default.fileExists(atPath: rootURL.appending(path: $0).path) }
        )
        for entry in status.entries {
            let path = normalized(entry.path)
            guard !path.isEmpty,
                FileManager.default.fileExists(atPath: rootURL.appending(path: path).path)
            else { continue }
            publishablePaths.insert(path)
        }
        return publishablePaths
    }

    private static func trackedPathsAndAncestors(_ trackedFilePaths: Set<String>) -> Set<String> {
        var paths = trackedFilePaths
        for trackedFilePath in trackedFilePaths {
            var components = trackedFilePath.split(separator: "/").map(String.init)
            while components.count > 1 {
                components.removeLast()
                paths.insert(components.joined(separator: "/"))
            }
        }
        return paths
    }

    private static func normalized(_ relativePath: String) -> String {
        var normalizedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalizedPath.hasPrefix("./") {
            normalizedPath.removeFirst(2)
        }
        while normalizedPath.hasPrefix("/") {
            normalizedPath.removeFirst()
        }
        return normalizedPath
    }
}
