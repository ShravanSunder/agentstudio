import Foundation

struct ZmxOrphanCleanupPlan: Equatable {
    let knownSessionIds: Set<String>
    let shouldSkipCleanup: Bool
    let unresolvedCandidateCount: Int
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

struct ZmxUnavailableInventorySummary: Equatable {
    let protectedSessionCount: Int
    let unresolvedCandidateCount: Int
}

enum ZmxOrphanCleanupCandidate: Equatable {
    case drawer(parentPaneId: UUID, paneId: UUID, storedSessionId: String?, derivedSessionId: String?)
    case main(paneId: UUID, storedSessionId: String?, derivedSessionId: String?)
}

enum ZmxOrphanCleanupPlanner {
    static func unavailableInventorySummary(
        candidates: [ZmxOrphanCleanupCandidate]
    ) -> ZmxUnavailableInventorySummary {
        let protectedSessionCount = candidates.filter(\.hasValidStoredSessionAnchor).count
        return .init(
            protectedSessionCount: protectedSessionCount,
            unresolvedCandidateCount: candidates.count - protectedSessionCount
        )
    }

    static func plan(
        candidates: [ZmxOrphanCleanupCandidate],
        liveSessionIds: Set<String>
    ) -> ZmxSessionAnchorHydrationPlan {
        var hasUnresolvablePane = false
        var unresolvedCandidateCount = 0
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

            let resolution = sessionResolution(for: candidate, liveSessionIds: liveSessionIds)
            guard let sessionIdForCleanup = resolution.sessionIdForCleanup else {
                hasUnresolvablePane = true
                unresolvedCandidateCount += 1
                continue
            }

            knownSessionIds.insert(sessionIdForCleanup)
            if let sessionIdToPersist = resolution.sessionIdToPersist {
                sessionIdsToPersistByPaneId[paneId] = sessionIdToPersist
            }
        }

        return ZmxSessionAnchorHydrationPlan(
            cleanupPlan: ZmxOrphanCleanupPlan(
                knownSessionIds: knownSessionIds,
                shouldSkipCleanup: hasUnresolvablePane,
                unresolvedCandidateCount: unresolvedCandidateCount,
                protectedMainPaneIds: protectedMainPaneIds,
                protectedDrawerPaneIds: protectedDrawerPaneIds
            ),
            sessionIdsToPersistByPaneId: sessionIdsToPersistByPaneId
        )
    }

    private static func sessionResolution(
        for candidate: ZmxOrphanCleanupCandidate,
        liveSessionIds: Set<String>
    ) -> ZmxSessionAnchorResolution {
        if let storedSessionId = candidate.storedSessionId {
            return .init(sessionIdForCleanup: storedSessionId, sessionIdToPersist: nil)
        }

        let liveMatches = liveSessionIds.filter { candidate.matchesLiveSessionId($0) }
        if liveMatches.count == 1 {
            let adoptedSessionId = liveMatches.first
            return .init(sessionIdForCleanup: adoptedSessionId, sessionIdToPersist: adoptedSessionId)
        }

        return .init(sessionIdForCleanup: candidate.derivedSessionId, sessionIdToPersist: nil)
    }
}

private struct ZmxSessionAnchorResolution {
    let sessionIdForCleanup: String?
    let sessionIdToPersist: String?
}

private enum ZmxOrphanCleanupCandidateKind {
    case main
    case drawer
}

extension ZmxOrphanCleanupCandidate {
    var hasValidStoredSessionAnchor: Bool {
        storedSessionId != nil
    }

    fileprivate var paneId: UUID {
        switch self {
        case .drawer(_, let paneId, _, _), .main(let paneId, _, _):
            paneId
        }
    }

    fileprivate var storedSessionId: String? {
        switch self {
        case .drawer(let parentPaneId, let paneId, let storedSessionId, _):
            guard let storedSessionId,
                ZmxBackend.isValidStoredDrawerSessionId(
                    storedSessionId,
                    parentPaneId: parentPaneId,
                    drawerPaneId: paneId
                )
            else {
                return nil
            }
            return storedSessionId
        case .main(let paneId, let storedSessionId, _):
            guard let storedSessionId,
                ZmxBackend.isValidStoredLayoutPaneSessionId(storedSessionId, paneId: paneId)
            else {
                return nil
            }
            return storedSessionId
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
