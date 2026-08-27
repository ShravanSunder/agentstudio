import AgentStudioGit
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

    private static func volumeSystemNumber(for path: String) -> UInt64? {
        var candidate = URL(fileURLWithPath: path)
        while candidate.path != "/", !FileManager.default.fileExists(atPath: candidate.path) {
            candidate.deleteLastPathComponent()
        }
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: candidate.path)
        return (attributes?[.systemNumber] as? NSNumber)?.uint64Value
    }
}
