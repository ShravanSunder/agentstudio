import CoreGraphics
import Foundation

enum DragDwellState: Equatable, Sendable {
    private static let timeComparisonTolerance = 0.000000001

    case idle
    case hovering(tabId: UUID, startTime: TimeInterval, lastCommittedTabId: UUID?)
    case committed(tabId: UUID, startTime: TimeInterval)

    var hoveredTabId: UUID? {
        switch self {
        case .idle:
            return nil
        case .hovering(let tabId, _, _), .committed(let tabId, _):
            return tabId
        }
    }

    var dwellStartTime: TimeInterval? {
        switch self {
        case .idle:
            return nil
        case .hovering(_, let startTime, _), .committed(_, let startTime):
            return startTime
        }
    }

    var lastCommittedTabId: UUID? {
        switch self {
        case .idle:
            return nil
        case .hovering(_, _, let lastCommittedTabId):
            return lastCommittedTabId
        case .committed(let tabId, _):
            return tabId
        }
    }

    static func step(
        current: Self,
        hoveredTabId: UUID?,
        now: TimeInterval,
        dwellDuration: TimeInterval
    ) -> (next: Self, shouldCommit: UUID?) {
        guard let hoveredTabId else {
            return (.idle, nil)
        }

        switch current {
        case .idle:
            return (.hovering(tabId: hoveredTabId, startTime: now, lastCommittedTabId: nil), nil)
        case .hovering(let currentTabId, let startTime, let lastCommittedTabId):
            if hoveredTabId != currentTabId {
                return (.hovering(tabId: hoveredTabId, startTime: now, lastCommittedTabId: lastCommittedTabId), nil)
            }
            if lastCommittedTabId == hoveredTabId {
                return (current, nil)
            }
            if now - startTime + timeComparisonTolerance >= dwellDuration {
                return (.committed(tabId: hoveredTabId, startTime: startTime), hoveredTabId)
            }
            return (current, nil)
        case .committed(let committedTabId, _):
            if hoveredTabId == committedTabId {
                return (current, nil)
            }
            return (.hovering(tabId: hoveredTabId, startTime: now, lastCommittedTabId: committedTabId), nil)
        }
    }
}

enum DragDwellProgress {
    private static let progressComparisonTolerance = 0.000000001

    static func progress(
        state: DragDwellState,
        now: TimeInterval,
        dwellDuration: TimeInterval
    ) -> CGFloat {
        switch state {
        case .idle, .committed:
            return 0
        case .hovering(let tabId, let startTime, let lastCommittedTabId):
            guard tabId != lastCommittedTabId else { return 0 }

            let rawProgress = (now - startTime) / dwellDuration
            let clampedProgress = max(0, min(1, rawProgress))
            if 1 - clampedProgress <= progressComparisonTolerance {
                return 1
            }
            return CGFloat(clampedProgress)
        }
    }
}
