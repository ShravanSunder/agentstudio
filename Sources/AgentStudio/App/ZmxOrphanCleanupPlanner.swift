import Foundation

struct ZmxOrphanCleanupPlan: Equatable {
    let knownSessionIds: Set<String>
    let shouldSkipCleanup: Bool
}

enum ZmxOrphanCleanupCandidate: Equatable {
    case drawer(parentPaneId: UUID, paneId: UUID)
    case main(paneId: UUID, repoStableKey: String?, worktreeStableKey: String?)
}

enum ZmxOrphanCleanupPlanner {
    static func plan(candidates: [ZmxOrphanCleanupCandidate]) -> ZmxOrphanCleanupPlan {
        var hasUnresolvableMainPane = false
        var knownSessionIds: Set<String> = []
        knownSessionIds.reserveCapacity(candidates.count)

        for candidate in candidates {
            switch candidate {
            case .drawer(let parentPaneId, let paneId):
                knownSessionIds.insert(
                    ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: paneId)
                )
            case .main(let paneId, let repoStableKey, let worktreeStableKey):
                guard let repoStableKey, let worktreeStableKey else {
                    hasUnresolvableMainPane = true
                    continue
                }
                knownSessionIds.insert(
                    ZmxBackend.sessionId(
                        repoStableKey: repoStableKey,
                        worktreeStableKey: worktreeStableKey,
                        paneId: paneId
                    )
                )
            }
        }

        return ZmxOrphanCleanupPlan(
            knownSessionIds: knownSessionIds,
            shouldSkipCleanup: hasUnresolvableMainPane
        )
    }
}
