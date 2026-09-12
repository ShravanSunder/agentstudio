import AgentStudioCore
import Foundation

enum ScopeChange: Sendable {
    case registerForgeRepo(repoId: UUID, remote: String)
    case unregisterForgeRepo(repoId: UUID)
    case refreshForgeRepo(repoId: UUID, correlationId: UUID?)
    case updateWatchedFolders(watchedPaths: [WatchedPath], restoringRepositories: [Repo], membershipRevision: UInt64)
    case updateTopologyMembershipRevision(UInt64)
}

extension ScopeChange: CustomStringConvertible {
    var description: String {
        switch self {
        case .registerForgeRepo(let repoId, let remote):
            return "registerForgeRepo(repoId: \(repoId.uuidString), remote: \(remote))"
        case .unregisterForgeRepo(let repoId):
            return "unregisterForgeRepo(repoId: \(repoId.uuidString))"
        case .refreshForgeRepo(let repoId, let correlationId):
            return
                "refreshForgeRepo(repoId: \(repoId.uuidString), correlationId: \(correlationId?.uuidString ?? "nil"))"
        case .updateTopologyMembershipRevision(let revision):
            return "updateTopologyMembershipRevision(\(revision))"
        case .updateWatchedFolders(let watchedPaths, _, _):
            return "updateWatchedFolders(count: \(watchedPaths.count))"
        }
    }
}
