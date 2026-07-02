import AgentStudioGit
import Foundation

struct BridgeWorktreeFileIgnorePolicy: Sendable {
    static let empty = Self(
        filesystemPathFilter: FilesystemPathFilter.empty,
        ignoredStatusPaths: []
    )

    private let filesystemPathFilter: FilesystemPathFilter
    private let ignoredStatusPaths: Set<String>

    static func load(rootURL: URL) async -> Self {
        async let filesystemPathFilter = FilesystemPathFilter.loadOffExecutor(forRootPath: rootURL)
        let ignoredStatusPaths = await ignoredStatusPaths(rootURL: rootURL)
        return await Self(
            filesystemPathFilter: filesystemPathFilter,
            ignoredStatusPaths: ignoredStatusPaths
        )
    }

    func isIgnored(relativePath: String) -> Bool {
        let normalizedPath = Self.normalized(relativePath)
        guard !normalizedPath.isEmpty, normalizedPath != "." else {
            return false
        }
        if ignoredStatusPaths.contains(normalizedPath) {
            return true
        }
        return filesystemPathFilter.isIgnored(relativePath: normalizedPath)
    }

    private static func ignoredStatusPaths(rootURL: URL) async -> Set<String> {
        do {
            let snapshot = try await LibGit2AgentStudioGitLocalClient().status(
                for: rootURL,
                options: GitStatusOptions(includeIgnored: true, includeUntracked: true)
            )
            return Set(
                snapshot.entries
                    .filter(\.ignored)
                    .map { normalized($0.path) }
                    .filter { !$0.isEmpty }
            )
        } catch {
            return []
        }
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
