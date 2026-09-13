import AgentStudioCore
import Foundation

enum ScopeChange: Sendable {
    case registerForgeRepo(repoId: UUID, remote: String, expectedLifetime: RepositoryObservationLifetime? = nil)
    case unregisterForgeRepo(repoId: UUID, expectedLifetime: RepositoryObservationLifetime? = nil)
    case refreshForgeRepo(repoId: UUID, correlationId: UUID?)
    case updateWatchedFolders(watchedPaths: [WatchedPath], restoringRepositories: [Repo], membershipRevision: UInt64)
    case updateRepositoryScanBaseline(repositories: [Repo], membershipRevision: UInt64)
}

extension ScopeChange: CustomStringConvertible {
    var description: String {
        switch self {
        case .registerForgeRepo(let repoId, let remote, _):
            return "registerForgeRepo(repoId: \(repoId.uuidString), remote: \(remote))"
        case .unregisterForgeRepo(let repoId, _):
            return "unregisterForgeRepo(repoId: \(repoId.uuidString))"
        case .refreshForgeRepo(let repoId, let correlationId):
            return
                "refreshForgeRepo(repoId: \(repoId.uuidString), correlationId: \(correlationId?.uuidString ?? "nil"))"
        case .updateRepositoryScanBaseline(_, let revision):
            return "updateRepositoryScanBaseline(\(revision))"
        case .updateWatchedFolders(let watchedPaths, _, _):
            return "updateWatchedFolders(count: \(watchedPaths.count))"
        }
    }
}
