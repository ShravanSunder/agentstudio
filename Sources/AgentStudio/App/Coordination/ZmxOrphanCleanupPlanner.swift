import Foundation

struct ZmxOrphanCleanupPlan: Equatable {
    let knownSessionIds: Set<String>
    let shouldSkipCleanup: Bool
    let protectedMainPaneIds: Set<UUID>
    let protectedDrawerPaneIds: Set<UUID>

    func destroyableOrphanSessionIds(from liveSessionIds: Set<String>) -> Set<String> {
        Set(liveSessionIds.filter { !protects(sessionId: $0) })
    }

    private func protects(sessionId: String) -> Bool {
        if knownSessionIds.contains(sessionId) {
            return true
        }
        if protectedMainPaneIds.contains(where: { ZmxBackend.mainSessionId(sessionId, matchesPaneId: $0) }) {
            return true
        }
        if protectedDrawerPaneIds.contains(where: { ZmxBackend.drawerSessionId(sessionId, matchesPaneId: $0) }) {
            return true
        }
        return false
    }
}

struct ZmxSessionAnchorHydrationPlan: Equatable {
    let cleanupPlan: ZmxOrphanCleanupPlan
    let sessionIdsToPersistByPaneId: [UUID: String]
}

enum ZmxOrphanCleanupCandidate: Equatable {
    case drawer(parentPaneId: UUID, paneId: UUID, storedSessionId: String?, derivedSessionId: String?)
    case main(paneId: UUID, storedSessionId: String?, derivedSessionId: String?)
}

enum ZmxOrphanCleanupPlanner {
    static func plan(
        candidates: [ZmxOrphanCleanupCandidate],
        liveSessionIds: Set<String>
    ) -> ZmxSessionAnchorHydrationPlan {
        var hasUnresolvablePane = false
        var knownSessionIds: Set<String> = []
        var protectedMainPaneIds: Set<UUID> = []
        var protectedDrawerPaneIds: Set<UUID> = []
        var sessionIdsToPersistByPaneId: [UUID: String] = [:]
        knownSessionIds.reserveCapacity(candidates.count)
        sessionIdsToPersistByPaneId.reserveCapacity(candidates.count)

        for candidate in candidates {
            let paneId = candidate.paneId
            switch candidate.kind {
            case .main:
                protectedMainPaneIds.insert(paneId)
            case .drawer:
                protectedDrawerPaneIds.insert(paneId)
            }

            let resolvedSessionId = resolvedSessionId(for: candidate, liveSessionIds: liveSessionIds)
            guard let resolvedSessionId else {
                hasUnresolvablePane = true
                continue
            }

            knownSessionIds.insert(resolvedSessionId)
            if candidate.storedSessionId == nil {
                sessionIdsToPersistByPaneId[paneId] = resolvedSessionId
            }
        }

        return ZmxSessionAnchorHydrationPlan(
            cleanupPlan: ZmxOrphanCleanupPlan(
                knownSessionIds: knownSessionIds,
                shouldSkipCleanup: hasUnresolvablePane,
                protectedMainPaneIds: protectedMainPaneIds,
                protectedDrawerPaneIds: protectedDrawerPaneIds
            ),
            sessionIdsToPersistByPaneId: sessionIdsToPersistByPaneId
        )
    }

    private static func resolvedSessionId(
        for candidate: ZmxOrphanCleanupCandidate,
        liveSessionIds: Set<String>
    ) -> String? {
        if let storedSessionId = candidate.storedSessionId {
            return storedSessionId
        }

        let liveMatches = liveSessionIds.filter { candidate.matchesLiveSessionId($0) }
        if liveMatches.count == 1 {
            return liveMatches.first
        }

        return candidate.derivedSessionId
    }
}

private enum ZmxOrphanCleanupCandidateKind {
    case main
    case drawer
}

extension ZmxOrphanCleanupCandidate {
    fileprivate var paneId: UUID {
        switch self {
        case .drawer(_, let paneId, _, _), .main(let paneId, _, _):
            paneId
        }
    }

    fileprivate var storedSessionId: String? {
        switch self {
        case .drawer(_, _, let storedSessionId, _), .main(_, let storedSessionId, _):
            storedSessionId
        }
    }

    fileprivate var derivedSessionId: String? {
        switch self {
        case .drawer(_, _, _, let derivedSessionId), .main(_, _, let derivedSessionId):
            derivedSessionId
        }
    }

    fileprivate var kind: ZmxOrphanCleanupCandidateKind {
        switch self {
        case .drawer:
            .drawer
        case .main:
            .main
        }
    }

    fileprivate func matchesLiveSessionId(_ sessionId: String) -> Bool {
        switch self {
        case .drawer(_, let paneId, _, _):
            ZmxBackend.drawerSessionId(sessionId, matchesPaneId: paneId)
        case .main(let paneId, _, _):
            ZmxBackend.mainSessionId(sessionId, matchesPaneId: paneId)
        }
    }
}
