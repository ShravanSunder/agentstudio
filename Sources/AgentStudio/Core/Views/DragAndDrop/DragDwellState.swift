import CoreGraphics
import Foundation

struct DragDwellState: Equatable, Sendable {
    private static let timeComparisonTolerance = 0.000000001

    var hoveredTabId: UUID?
    var dwellStartTime: TimeInterval?
    var lastCommittedTabId: UUID?

    static let idle = Self()

    static func step(
        current: Self,
        hoveredTabId: UUID?,
        now: TimeInterval,
        dwellDuration: TimeInterval
    ) -> (next: Self, shouldCommit: UUID?) {
        guard let hoveredTabId else {
            return (
                Self(
                    hoveredTabId: nil,
                    dwellStartTime: nil,
                    lastCommittedTabId: current.lastCommittedTabId
                ),
                nil
            )
        }

        if hoveredTabId != current.hoveredTabId {
            return (
                Self(
                    hoveredTabId: hoveredTabId,
                    dwellStartTime: now,
                    lastCommittedTabId: current.lastCommittedTabId
                ),
                nil
            )
        }

        guard let startTime = current.dwellStartTime else {
            return (
                Self(
                    hoveredTabId: hoveredTabId,
                    dwellStartTime: now,
                    lastCommittedTabId: current.lastCommittedTabId
                ),
                nil
            )
        }

        if current.lastCommittedTabId == hoveredTabId {
            return (current, nil)
        }

        if now - startTime + timeComparisonTolerance >= dwellDuration {
            return (
                Self(
                    hoveredTabId: hoveredTabId,
                    dwellStartTime: startTime,
                    lastCommittedTabId: hoveredTabId
                ),
                hoveredTabId
            )
        }

        return (current, nil)
    }
}

enum DragDwellProgress {
    private static let progressComparisonTolerance = 0.000000001

    static func progress(
        state: DragDwellState,
        now: TimeInterval,
        dwellDuration: TimeInterval
    ) -> CGFloat {
        guard
            let startTime = state.dwellStartTime,
            state.hoveredTabId != nil,
            state.hoveredTabId != state.lastCommittedTabId
        else {
            return 0
        }

        let rawProgress = (now - startTime) / dwellDuration
        let clampedProgress = max(0, min(1, rawProgress))
        if 1 - clampedProgress <= progressComparisonTolerance {
            return 1
        }
        return CGFloat(clampedProgress)
    }
}
