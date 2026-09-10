import AgentStudioGit
import CoreServices
import Foundation

package enum DarwinFSEventStreamConfiguration {
    package static let continuityFlags = FSEventStreamCreateFlags(
        kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagWatchRoot
            | kFSEventStreamCreateFlagMarkSelf
    )

    package static func privateStagingExclusionPaths(
        observationScopes: [AgentStudioGit.GitStatusObservationScope]
    ) -> [String] {
        Set(
            observationScopes.compactMap { scope -> String? in
                guard scope.kind == .subtree, scope.path.lastPathComponent == "refs" else {
                    return nil
                }
                return scope.path.appending(path: "agentstudio/staged", directoryHint: .isDirectory).path
            }
        ).sorted()
    }

    package static func privateStagingExclusionPaths(
        sharedParentPath: String
    ) -> [String] {
        let parentURL = URL(fileURLWithPath: sharedParentPath, isDirectory: true)
        let refsURL =
            parentURL.lastPathComponent == "refs"
            ? parentURL
            : parentURL.appendingPathComponent("refs", isDirectory: true)
        return [refsURL.appendingPathComponent("agentstudio/staged", isDirectory: true).path]
    }

    static func installPrivateStagingExclusions(
        _ exclusionPaths: [String],
        on stream: FSEventStreamRef
    ) -> Bool {
        guard !exclusionPaths.isEmpty else { return true }
        return FSEventStreamSetExclusionPaths(
            stream,
            exclusionPaths.map { $0 as NSString } as CFArray
        )
    }
}
