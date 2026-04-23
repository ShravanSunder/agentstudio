import CoreGraphics
import Foundation

struct PaneDropTarget: Equatable, Hashable {
    let paneId: UUID
    let zone: DropZoneSide
    let sizingTarget: DropTarget

    init(paneId: UUID, zone: DropZoneSide, sizingTarget: DropTarget? = nil) {
        self.paneId = paneId
        self.zone = zone
        self.sizingTarget = sizingTarget ?? .paneSplit(paneId: self.paneId, side: self.zone)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.paneId == rhs.paneId && lhs.zone == rhs.zone
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(paneId)
        hasher.combine(zone)
    }
}

struct PaneDragCoordinator {
    static let edgeCorridorWidth: CGFloat = 24

    static func resolveTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect? = nil,
        minimizedPaneIds: Set<UUID>
    ) -> PaneDropTarget? {
        let sortedPaneIds = sortedPaneIds(from: paneFrames)
        let effectiveBounds = containerBounds ?? derivedBounds(from: paneFrames)
        let splittablePaneIds = Set(paneFrames.keys).subtracting(minimizedPaneIds)

        guard
            let target = DropTargetResolver.resolve(
                location: location,
                rows: [.main: sortedPaneIds],
                paneFrames: paneFrames,
                containerBounds: effectiveBounds,
                config: .main,
                splittablePanes: splittablePaneIds
            )
        else {
            return nil
        }

        return paneTarget(from: target, sortedPaneIds: sortedPaneIds)
    }

    static func resolveLatchedTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect? = nil,
        minimizedPaneIds: Set<UUID>,
        currentTarget: PaneDropTarget?,
        shouldAcceptDrop: (UUID, DropZoneSide) -> Bool
    ) -> PaneDropTarget? {
        let sortedPaneIds = sortedPaneIds(from: paneFrames)
        let effectiveBounds = containerBounds ?? derivedBounds(from: paneFrames)
        let splittablePaneIds = Set(paneFrames.keys).subtracting(minimizedPaneIds)
        let currentDropTarget = currentTarget.flatMap {
            dropTarget(from: $0, sortedPaneIds: sortedPaneIds)
        }

        guard
            let target = DropTargetResolver.resolveLatched(
                location: location,
                rows: [.main: sortedPaneIds],
                paneFrames: paneFrames,
                containerBounds: effectiveBounds,
                config: .main,
                splittablePanes: splittablePaneIds,
                currentTarget: currentDropTarget,
                shouldAccept: { target in
                    guard let paneTarget = paneTarget(from: target, sortedPaneIds: sortedPaneIds) else { return false }
                    return shouldAcceptDrop(paneTarget.paneId, paneTarget.zone)
                }
            )
        else {
            return nil
        }

        return paneTarget(from: target, sortedPaneIds: sortedPaneIds)
    }

    static func targetRects(
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        minimizedPaneIds: Set<UUID>
    ) -> [PaneDropTarget: CGRect] {
        let sortedPaneIds = sortedPaneIds(from: paneFrames)
        let splittablePaneIds = Set(paneFrames.keys).subtracting(minimizedPaneIds)
        let sharedRects = DropTargetResolver.targetRects(
            rows: [.main: sortedPaneIds],
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            config: .main,
            splittablePanes: splittablePaneIds
        )

        var rects: [PaneDropTarget: CGRect] = sharedRects.reduce(into: [:]) { translatedRects, entry in
            guard let paneTarget = paneTarget(from: entry.key, sortedPaneIds: sortedPaneIds) else { return }
            translatedRects[paneTarget] = entry.value
        }

        for paneId in splittablePaneIds {
            guard let paneFrame = paneFrames[paneId] else { continue }
            rects[PaneDropTarget(paneId: paneId, zone: .left)] = CGRect(
                x: paneFrame.minX,
                y: paneFrame.minY,
                width: paneFrame.width / 2,
                height: paneFrame.height
            )
            rects[PaneDropTarget(paneId: paneId, zone: .right)] = CGRect(
                x: paneFrame.midX,
                y: paneFrame.minY,
                width: paneFrame.width / 2,
                height: paneFrame.height
            )
        }

        return rects
    }

    private static func sortedPaneIds(from paneFrames: [UUID: CGRect]) -> [UUID] {
        paneFrames.keys.sorted { lhs, rhs in
            guard let lhsFrame = paneFrames[lhs], let rhsFrame = paneFrames[rhs] else {
                return lhs.uuidString < rhs.uuidString
            }
            if lhsFrame.minX != rhsFrame.minX {
                return lhsFrame.minX < rhsFrame.minX
            }
            if lhsFrame.minY != rhsFrame.minY {
                return lhsFrame.minY < rhsFrame.minY
            }
            return lhs.uuidString < rhs.uuidString
        }
    }

    private static func derivedBounds(from frames: [UUID: CGRect]) -> CGRect {
        let minX = frames.values.map(\.minX).min() ?? 0
        let maxX = frames.values.map(\.maxX).max() ?? 0
        let minY = frames.values.map(\.minY).min() ?? 0
        let maxY = frames.values.map(\.maxY).max() ?? 0
        return CGRect(
            x: minX - edgeCorridorWidth,
            y: minY,
            width: maxX - minX + edgeCorridorWidth * 2,
            height: maxY - minY
        )
    }

    private static func paneTarget(from target: DropTarget, sortedPaneIds: [UUID]) -> PaneDropTarget? {
        switch target {
        case .paneSplit(let paneId, let side):
            return PaneDropTarget(paneId: paneId, zone: side, sizingTarget: target)
        case .paneSlot(_, let index):
            return paneTarget(slotIndex: index, sortedPaneIds: sortedPaneIds, sizingTarget: target)
        case .paneNewRow:
            return nil
        }
    }

    private static func paneTarget(
        slotIndex: Int,
        sortedPaneIds: [UUID],
        sizingTarget: DropTarget
    ) -> PaneDropTarget? {
        guard !sortedPaneIds.isEmpty else { return nil }
        if slotIndex <= 0 {
            return PaneDropTarget(paneId: sortedPaneIds[0], zone: .left, sizingTarget: sizingTarget)
        }
        if slotIndex >= sortedPaneIds.count {
            guard let lastPaneId = sortedPaneIds.last else { return nil }
            return PaneDropTarget(paneId: lastPaneId, zone: .right, sizingTarget: sizingTarget)
        }
        return PaneDropTarget(paneId: sortedPaneIds[slotIndex - 1], zone: .right, sizingTarget: sizingTarget)
    }

    private static func dropTarget(from target: PaneDropTarget, sortedPaneIds: [UUID]) -> DropTarget? {
        switch target.sizingTarget {
        case .paneSlot, .paneSplit:
            return target.sizingTarget
        case .paneNewRow:
            break
        }
        guard let index = sortedPaneIds.firstIndex(of: target.paneId) else { return nil }
        switch target.zone {
        case .left:
            return .paneSlot(row: .main, index: index)
        case .right:
            return .paneSlot(row: .main, index: index + 1)
        }
    }

}
