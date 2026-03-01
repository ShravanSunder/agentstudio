import Foundation

struct FilesystemOwnedPath: Sendable, Equatable {
    let worktreeId: UUID
    let relativePath: String
}

struct FilesystemRootOwnership: Sendable {
    private struct Root: Sendable {
        let worktreeId: UUID
        let canonicalPath: String
        let comparisonPath: String
    }

    private let roots: [Root]
    private let sourceRootByWorktreeId: [UUID: Root]

    init(rootsByWorktree: [UUID: URL]) {
        let resolvedRoots = rootsByWorktree.map { worktreeId, rootPath in
            let canonicalPath = Self.canonicalRootPath(for: rootPath)
            return Root(
                worktreeId: worktreeId,
                canonicalPath: canonicalPath,
                comparisonPath: Self.normalizedComparisonKey(canonicalPath)
            )
        }
        self.roots = resolvedRoots
        self.sourceRootByWorktreeId = Dictionary(uniqueKeysWithValues: resolvedRoots.map { ($0.worktreeId, $0) })
    }

    static func canonicalRootPath(for rootPath: URL) -> String {
        canonicalize(path: rootPath.path)
    }

    func route(sourceWorktreeId: UUID, rawPath: String) -> FilesystemOwnedPath? {
        guard let sourceRoot = sourceRootByWorktreeId[sourceWorktreeId] else {
            return nil
        }
        let canonicalPath = Self.canonicalize(rawPath: rawPath, sourceRootPath: sourceRoot.canonicalPath)
        guard let owner = owningRoot(forCanonicalPath: canonicalPath) else {
            return nil
        }

        let relativePath = Self.relativePath(
            canonicalPath: canonicalPath,
            ownerRootCanonicalPath: owner.canonicalPath
        )
        return FilesystemOwnedPath(worktreeId: owner.worktreeId, relativePath: relativePath)
    }

    private func owningRoot(forCanonicalPath canonicalPath: String) -> Root? {
        let pathKey = Self.normalizedComparisonKey(canonicalPath)
        return
            roots
            .filter { root in
                Self.isDescendantPath(pathKey, of: root.comparisonPath)
            }
            .max { lhs, rhs in
                if lhs.comparisonPath.count != rhs.comparisonPath.count {
                    return lhs.comparisonPath.count < rhs.comparisonPath.count
                }
                return lhs.worktreeId.uuidString < rhs.worktreeId.uuidString
            }
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

    private static func canonicalize(rawPath: String, sourceRootPath: String) -> String {
        let normalizedInput = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedInput.isEmpty else { return sourceRootPath }

        if normalizedInput.hasPrefix("/") {
            return canonicalize(path: normalizedInput)
        }

        let joinedPath = URL(fileURLWithPath: sourceRootPath)
            .appending(path: normalizedInput)
            .path
        return canonicalize(path: joinedPath)
    }

    private static func canonicalize(path: String) -> String {
        let canonicalURL = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        return trimTrailingSlash(from: canonicalURL.path)
    }

    private static func relativePath(
        canonicalPath: String,
        ownerRootCanonicalPath: String
    ) -> String {
        if canonicalPath.compare(ownerRootCanonicalPath, options: [.caseInsensitive]) == .orderedSame {
            return "."
        }

        let ownerPrefix = ownerRootCanonicalPath == "/" ? "/" : ownerRootCanonicalPath + "/"
        if let ownerRange = canonicalPath.range(of: ownerPrefix, options: [.anchored, .caseInsensitive]) {
            let suffix = String(canonicalPath[ownerRange.upperBound...])
            return suffix.isEmpty ? "." : suffix
        }
        return "."
    }

    private static func normalizedComparisonKey(_ path: String) -> String {
        path.lowercased()
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
