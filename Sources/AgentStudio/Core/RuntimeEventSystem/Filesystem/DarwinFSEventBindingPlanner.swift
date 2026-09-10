import AgentStudioGit
import Darwin
import Foundation

package struct DarwinSharedExactItemParentKey: Hashable, Sendable {
    package let parentPath: String
    package let volumeSystemNumber: UInt64
}

package struct DarwinFSEventBindingPlan: Sendable {
    package let localScopes: [AgentStudioGit.GitStatusObservationScope]
    package let localWatchedPaths: [String]
    package let sharedExactItemsByParent: [DarwinSharedExactItemParentKey: Set<String>]
}

package enum DarwinFSEventBindingPlanner {
    package static func plan(
        observationPlan: AgentStudioGit.GitStatusObservationPlan
    ) -> DarwinFSEventBindingPlan? {
        guard !observationPlan.scopes.isEmpty else { return nil }
        let scopes = observationPlan.scopes.map { scope in
            AgentStudioGit.GitStatusObservationScope(
                kind: scope.kind,
                path: DarwinFSEventPathCanonicalizer.canonicalURL(scope.path)
            )
        }
        guard let binding = plan(scopes: scopes) else { return nil }
        guard pathsShareVolume(binding.localWatchedPaths) else { return nil }
        return binding
    }

    package static func plan(
        scopes: [AgentStudioGit.GitStatusObservationScope],
        volumeSystemNumberForPath: (String) -> UInt64? = volumeSystemNumber(for:)
    ) -> DarwinFSEventBindingPlan? {
        guard !scopes.isEmpty else { return nil }

        let subtreeScopes = scopes.filter { $0.kind == .subtree }
        let subtreePaths = Set(subtreeScopes.map { $0.path.path })
        guard !subtreePaths.isEmpty else { return nil }

        var localScopes = subtreeScopes
        var sharedExactItemsByParent: [DarwinSharedExactItemParentKey: Set<String>] = [:]

        for itemScope in scopes where itemScope.kind == .item {
            let itemPath = itemScope.path.path
            if subtreePaths.contains(where: { subtreePath in
                itemPath == subtreePath || itemPath.hasPrefix(subtreePath + "/")
            }) {
                localScopes.append(itemScope)
                continue
            }

            let parentPath = itemScope.path.deletingLastPathComponent().path
            guard let volumeSystemNumber = volumeSystemNumberForPath(parentPath) else { return nil }
            let parentKey = DarwinSharedExactItemParentKey(
                parentPath: parentPath,
                volumeSystemNumber: volumeSystemNumber
            )
            sharedExactItemsByParent[parentKey, default: []].insert(itemPath)
        }

        return DarwinFSEventBindingPlan(
            localScopes: localScopes,
            localWatchedPaths: subtreePaths.sorted(),
            sharedExactItemsByParent: sharedExactItemsByParent
        )
    }

    package static func scopesMatch(
        _ lhs: [AgentStudioGit.GitStatusObservationScope],
        _ rhs: [AgentStudioGit.GitStatusObservationScope]
    ) -> Bool {
        lhs.count == rhs.count
            && zip(lhs, rhs).allSatisfy { lhsScope, rhsScope in
                lhsScope.kind == rhsScope.kind && lhsScope.path == rhsScope.path
            }
    }

    private static func pathsShareVolume(_ paths: [String]) -> Bool {
        let volumeNumbers = paths.compactMap { path -> NSNumber? in
            var candidate = URL(fileURLWithPath: path)
            while candidate.path != "/", !FileManager.default.fileExists(atPath: candidate.path) {
                candidate.deleteLastPathComponent()
            }
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: candidate.path)
            return attributes?[.systemNumber] as? NSNumber
        }
        return volumeNumbers.count == paths.count && Set(volumeNumbers).count == 1
    }

    package static func volumeSystemNumber(for path: String) -> UInt64? {
        var candidate = URL(fileURLWithPath: path)
        while candidate.path != "/", !FileManager.default.fileExists(atPath: candidate.path) {
            candidate.deleteLastPathComponent()
        }
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: candidate.path)
        return (attributes?[.systemNumber] as? NSNumber)?.uint64Value
    }
}

package enum DarwinFSEventPathCanonicalizer {
    package static func canonicalURL(_ url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        var existingAncestor = standardizedURL
        var unresolvedComponents: [String] = []

        while true {
            if let resolvedPath = realPath(existingAncestor.path) {
                return unresolvedComponents.reversed().reduce(
                    URL(fileURLWithPath: resolvedPath)
                ) { resolvedURL, component in
                    resolvedURL.appending(path: component)
                }
            }
            guard existingAncestor.path != "/" else {
                return standardizedURL.resolvingSymlinksInPath()
            }
            unresolvedComponents.append(existingAncestor.lastPathComponent)
            existingAncestor.deleteLastPathComponent()
        }
    }

    private static func realPath(_ path: String) -> String? {
        path.withCString { pathPointer in
            guard let resolvedPointer = Darwin.realpath(pathPointer, nil) else { return nil }
            defer { free(resolvedPointer) }
            return String(cString: resolvedPointer)
        }
    }
}
