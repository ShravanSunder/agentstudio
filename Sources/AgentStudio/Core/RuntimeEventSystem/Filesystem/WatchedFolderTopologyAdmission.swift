import AgentStudioInfrastructure
import CoreServices
import Foundation

/// Interprets source facts without I/O; ordinary work inside a known checkout cannot change scan membership.
enum WatchedFolderTopologyAdmission {
    static func shouldScan(
        _ batch: FSEventBatch, root: RegisteredRootDescriptor, knownGroups: [RepoScanner.RepoScanGroup]
    ) -> Bool {
        if batch.paths.contains(where: isGitTopologyPath) || batch.requiresFullGitRefresh
            || batch.observations.contains(where: \.hasCoverageLoss)
        {
            return true
        }
        guard batch.observations.contains(where: isDirectoryStructureChange) else { return false }
        let canonicalRoot = comparisonPath(
            root.aliases.onceResolvedCanonical.path, policy: root.volumeSemantics.casePolicy)
        let lexicalRoot = comparisonPath(root.aliases.standardizedLexical.path, policy: root.volumeSemantics.casePolicy)
        let knownPaths = knownGroups.flatMap { [$0.clonePath] + $0.linkedWorktreePaths }
            .map { comparisonPath($0.path, policy: root.volumeSemantics.casePolicy) }
        return batch.observations.contains { observation in
            guard isDirectoryStructureChange(observation) else { return false }
            var path = comparisonPath(observation.path, policy: root.volumeSemantics.casePolicy)
            if contains(path, within: lexicalRoot) {
                path = canonicalRoot + path.dropFirst(lexicalRoot.count)
            }
            guard contains(path, within: canonicalRoot) else { return false }
            return !knownPaths.contains { path != $0 && contains(path, within: $0) }
        }
    }

    /// Overflow can lose precise observations, so retain whether the lost batch could require membership recovery.
    static func mayAffectTopology(_ batch: FSEventBatch) -> Bool {
        batch.requiresFullGitRefresh || batch.paths.contains(where: isGitTopologyPath)
            || batch.observations.contains { $0.hasCoverageLoss || isDirectoryStructureChange($0) }
    }

    private static func isDirectoryStructureChange(_ observation: FSEventObservation) -> Bool {
        let directoryFlag = UInt32(kFSEventStreamEventFlagItemIsDir)
        let structureFlags = UInt32(
            kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed
        )
        return observation.flags & directoryFlag != 0 && observation.flags & structureFlags != 0
    }

    private static func isGitTopologyPath(_ path: String) -> Bool {
        path.contains("/.git/") || path.hasSuffix("/.git")
    }

    private static func comparisonPath(_ path: String, policy: FilesystemVolumeCasePolicy) -> String {
        let normalized = FilesystemRootOwnership.canonicalizeKernelPath(path).precomposedStringWithCanonicalMapping
        return policy == .caseInsensitive ? normalized.lowercased() : normalized
    }

    private static func contains(_ path: String, within root: String) -> Bool {
        root == "/" || path == root || path.hasPrefix(root + "/")
    }
}
