import Foundation

struct ZmxOrphanCleanupPlan: Equatable {
    let knownSessionIds: Set<String>
    let protectedPaneSegments: Set<String>

    func protects(sessionId: String) -> Bool {
        knownSessionIds.contains(sessionId)
            || protectedPaneSegments.contains { sessionId.contains($0) }
    }

    func destroyableSessionIds(from discoveredSessionIds: [String]) -> [String] {
        discoveredSessionIds.filter { sessionId in
            ZmxBackend.isAgentStudioSessionId(sessionId)
                && !protects(sessionId: sessionId)
        }
    }
}

enum ZmxOrphanCleanupCandidate: Equatable {
    case drawer(parentPaneId: UUID, paneId: UUID)
    case main(paneId: UUID, repoStableKey: String?, worktreeStableKey: String?)
}

enum ZmxOrphanCleanupPlanner {
    static func plan(candidates: [ZmxOrphanCleanupCandidate]) -> ZmxOrphanCleanupPlan {
        var knownSessionIds: Set<String> = []
        var protectedPaneSegments: Set<String> = []
        knownSessionIds.reserveCapacity(candidates.count)
        protectedPaneSegments.reserveCapacity(candidates.count)

        for candidate in candidates {
            switch candidate {
            case .drawer(let parentPaneId, let paneId):
                knownSessionIds.insert(
                    ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: paneId)
                )
            case .main(let paneId, let repoStableKey, let worktreeStableKey):
                guard let repoStableKey, let worktreeStableKey else {
                    protectedPaneSegments.insert(ZmxBackend.paneSessionSegment(paneId))
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
            protectedPaneSegments: protectedPaneSegments
        )
    }
}
