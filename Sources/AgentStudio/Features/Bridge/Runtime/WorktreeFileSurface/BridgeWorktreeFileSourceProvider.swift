import Foundation

struct BridgeWorktreeFileOpenedSource: Sendable {
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let canonicalCwdScope: String
    let canonicalPathScope: [String]
    let ignorePolicy: BridgeWorktreeFileIgnorePolicy
    let includeStatuses: Bool

    func withIgnorePolicy(_ ignorePolicy: BridgeWorktreeFileIgnorePolicy) -> Self {
        Self(
            source: source,
            canonicalCwdScope: canonicalCwdScope,
            canonicalPathScope: canonicalPathScope,
            ignorePolicy: ignorePolicy,
            includeStatuses: includeStatuses
        )
    }
}

enum BridgeWorktreeFileSourceProviderError: Error, Equatable, Sendable {
    case worktreeMismatch
    case rootTokenMismatch
    case selectorEscapesRoot
    case unsupportedReservedContract
}

enum BridgeWorktreeFileSourceProvider {
    static func openSource(
        spec: BridgeWorktreeFileSurfaceSourceSpec,
        worktree: Worktree,
        paneIdentity: UUID? = nil,
        subscriptionGeneration: Int
    ) throws -> BridgeWorktreeFileOpenedSource {
        guard spec.repoId == worktree.repoId, spec.worktreeId == worktree.id else {
            throw BridgeWorktreeFileSourceProviderError.worktreeMismatch
        }
        guard spec.rootPathToken == worktree.stableKey else {
            throw BridgeWorktreeFileSourceProviderError.rootTokenMismatch
        }
        guard !spec.includeComments, !spec.includeAgentComms else {
            throw BridgeWorktreeFileSourceProviderError.unsupportedReservedContract
        }

        let rootPath = canonicalPath(for: worktree.path.path)
        let cwdPath = try canonicalScopedPath(
            selector: spec.cwdScope,
            basePath: rootPath,
            rootPath: rootPath
        )
        let canonicalPathScope = try spec.pathScope.map { pathSelector in
            try relativeScopedPath(
                selector: pathSelector,
                basePath: cwdPath,
                rootPath: rootPath
            )
        }
        let sourceIdentityPrefix = paneIdentity.map { "pane-\($0.uuidString)-" } ?? ""
        let source = BridgeWorktreeFileSurfaceSourceIdentity(
            sourceId:
                "\(sourceIdentityPrefix)worktree-\(worktree.id.uuidString)-\(subscriptionGeneration)",
            repoId: worktree.repoId.uuidString,
            worktreeId: worktree.id.uuidString,
            subscriptionGeneration: subscriptionGeneration,
            sourceCursor: "generation-\(subscriptionGeneration)",
            rootRevisionToken: worktree.stableKey
        )

        return BridgeWorktreeFileOpenedSource(
            source: source,
            canonicalCwdScope: relativePath(canonicalPath: cwdPath, rootPath: rootPath),
            canonicalPathScope: canonicalPathScope,
            ignorePolicy: .empty,
            includeStatuses: spec.includeStatuses
        )
    }

    private static func relativeScopedPath(
        selector: String,
        basePath: String,
        rootPath: String
    ) throws -> String {
        let path = try canonicalScopedPath(
            selector: selector,
            basePath: basePath,
            rootPath: rootPath
        )
        return relativePath(canonicalPath: path, rootPath: rootPath)
    }

    private static func canonicalScopedPath(
        selector: String?,
        basePath: String,
        rootPath: String
    ) throws -> String {
        let rawSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scopedPath: String
        if rawSelector.isEmpty {
            scopedPath = basePath
        } else if rawSelector.hasPrefix("/") {
            scopedPath = canonicalPath(for: rawSelector)
        } else {
            scopedPath = canonicalPath(for: URL(fileURLWithPath: basePath).appending(path: rawSelector).path)
        }

        guard isDescendantPath(scopedPath, of: rootPath) else {
            throw BridgeWorktreeFileSourceProviderError.selectorEscapesRoot
        }
        return scopedPath
    }

    private static func isDescendantPath(_ path: String, of rootPath: String) -> Bool {
        if path == rootPath {
            return true
        }
        if rootPath == "/" {
            return path.hasPrefix("/")
        }
        return path.hasPrefix(rootPath + "/")
    }

    private static func relativePath(canonicalPath: String, rootPath: String) -> String {
        if canonicalPath == rootPath {
            return "."
        }

        let rootPrefix = rootPath == "/" ? "/" : rootPath + "/"
        guard let rootRange = canonicalPath.range(of: rootPrefix, options: [.anchored]) else {
            return "."
        }
        let suffix = String(canonicalPath[rootRange.upperBound...])
        return suffix.isEmpty ? "." : suffix
    }

    private static func canonicalPath(for path: String) -> String {
        let canonicalURL = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        return trimTrailingSlash(from: canonicalURL.path)
    }

    private static func trimTrailingSlash(from path: String) -> String {
        guard path != "/" else { return path }
        var value = path
        while value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
