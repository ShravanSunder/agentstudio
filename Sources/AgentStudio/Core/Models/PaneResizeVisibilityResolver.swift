import Foundation

struct VisiblePaneResizePair: Equatable, Hashable, Sendable {
    let leftPaneId: UUID
    let rightPaneId: UUID
}

enum PaneResizeVisibilityResolver {
    static func pairAroundDivider(
        layout: Layout,
        dividerIndex: Int,
        minimizedPaneIds: Set<UUID>
    ) -> VisiblePaneResizePair? {
        guard dividerIndex >= 0, dividerIndex < layout.dividerIds.count else { return nil }
        let leftIndex = dividerIndex
        let rightIndex = dividerIndex + 1
        let leftPaneId = layout.panes[leftIndex].paneId
        let rightPaneId = layout.panes[rightIndex].paneId
        let leftIsMinimized = minimizedPaneIds.contains(leftPaneId)
        let rightIsMinimized = minimizedPaneIds.contains(rightPaneId)

        if !leftIsMinimized, !rightIsMinimized {
            return VisiblePaneResizePair(leftPaneId: leftPaneId, rightPaneId: rightPaneId)
        }
        if !leftIsMinimized, rightIsMinimized {
            guard
                let visibleRightIndex = nextVisibleIndex(
                    after: rightIndex, layout: layout, minimizedPaneIds: minimizedPaneIds)
            else { return nil }
            return VisiblePaneResizePair(leftPaneId: leftPaneId, rightPaneId: layout.panes[visibleRightIndex].paneId)
        }
        if leftIsMinimized, !rightIsMinimized {
            guard
                let visibleLeftIndex = previousVisibleIndex(
                    before: leftIndex,
                    layout: layout,
                    minimizedPaneIds: minimizedPaneIds
                )
            else { return nil }
            return VisiblePaneResizePair(leftPaneId: layout.panes[visibleLeftIndex].paneId, rightPaneId: rightPaneId)
        }
        return nil
    }

    static func validatesCollapsedRunPair(
        layoutPaneIds: [UUID],
        minimizedPaneIds: Set<UUID>,
        leftPaneId: UUID,
        rightPaneId: UUID
    ) -> Bool {
        guard
            leftPaneId != rightPaneId,
            let leftIndex = layoutPaneIds.firstIndex(of: leftPaneId),
            let rightIndex = layoutPaneIds.firstIndex(of: rightPaneId),
            leftIndex < rightIndex,
            !minimizedPaneIds.contains(leftPaneId),
            !minimizedPaneIds.contains(rightPaneId),
            rightIndex - leftIndex > 1
        else { return false }

        return layoutPaneIds[(leftIndex + 1)..<rightIndex].allSatisfy { minimizedPaneIds.contains($0) }
    }

    static func keyboardPair(
        layout: Layout,
        minimizedPaneIds: Set<UUID>,
        paneId: UUID,
        direction: SplitResizeDirection
    ) -> (pair: VisiblePaneResizePair, increase: Bool)? {
        guard let paneIndex = layout.panes.firstIndex(where: { $0.paneId == paneId }) else { return nil }
        switch direction {
        case .left:
            guard paneIndex > 0 else { return nil }
            let leftNeighbor = layout.panes[paneIndex - 1].paneId
            if !minimizedPaneIds.contains(leftNeighbor) {
                return (VisiblePaneResizePair(leftPaneId: leftNeighbor, rightPaneId: paneId), false)
            }
            guard
                let visibleLeftIndex = previousVisibleIndex(
                    before: paneIndex - 1,
                    layout: layout,
                    minimizedPaneIds: minimizedPaneIds
                )
            else { return nil }
            return (
                VisiblePaneResizePair(leftPaneId: layout.panes[visibleLeftIndex].paneId, rightPaneId: paneId), false
            )
        case .right:
            guard paneIndex < layout.panes.index(before: layout.panes.endIndex) else { return nil }
            let rightNeighbor = layout.panes[paneIndex + 1].paneId
            if !minimizedPaneIds.contains(rightNeighbor) {
                return (VisiblePaneResizePair(leftPaneId: paneId, rightPaneId: rightNeighbor), true)
            }
            guard
                let visibleRightIndex = nextVisibleIndex(
                    after: paneIndex + 1,
                    layout: layout,
                    minimizedPaneIds: minimizedPaneIds
                )
            else { return nil }
            return (
                VisiblePaneResizePair(leftPaneId: paneId, rightPaneId: layout.panes[visibleRightIndex].paneId), true
            )
        case .up, .down:
            return nil
        }
    }

    private static func previousVisibleIndex(
        before index: Int,
        layout: Layout,
        minimizedPaneIds: Set<UUID>
    ) -> Int? {
        guard index > 0 else { return nil }
        for candidateIndex in stride(from: index - 1, through: 0, by: -1) {
            if !minimizedPaneIds.contains(layout.panes[candidateIndex].paneId) {
                return candidateIndex
            }
        }
        return nil
    }

    private static func nextVisibleIndex(
        after index: Int,
        layout: Layout,
        minimizedPaneIds: Set<UUID>
    ) -> Int? {
        guard index < layout.panes.index(before: layout.panes.endIndex) else { return nil }
        for candidateIndex in (index + 1)..<layout.panes.count {
            if !minimizedPaneIds.contains(layout.panes[candidateIndex].paneId) {
                return candidateIndex
            }
        }
        return nil
    }
}
