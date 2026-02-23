import CoreGraphics
import Foundation

struct PaneDropTarget: Equatable {
    let paneId: UUID
    let zone: DropZone
}

struct PaneDragCoordinator {
    static let edgeCorridorWidth: CGFloat = 24

    static func resolveTarget(location: CGPoint, paneFrames: [UUID: CGRect]) -> PaneDropTarget? {
        if let containedTarget = resolveContainedTarget(location: location, paneFrames: paneFrames) {
            return containedTarget
        }
        return resolveEdgeCorridorTarget(location: location, paneFrames: paneFrames)
    }

    static func resolveLatchedTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        currentTarget: PaneDropTarget?,
        shouldAcceptDrop: (UUID, DropZone) -> Bool
    ) -> PaneDropTarget? {
        if let resolvedTarget = resolveTarget(location: location, paneFrames: paneFrames),
            shouldAcceptDrop(resolvedTarget.paneId, resolvedTarget.zone)
        {
            return resolvedTarget
        }

        if let currentTarget,
            shouldAcceptDrop(currentTarget.paneId, currentTarget.zone)
        {
            return currentTarget
        }

        return nil
    }

    private static func resolveContainedTarget(location: CGPoint, paneFrames: [UUID: CGRect]) -> PaneDropTarget? {
        let containingPanes = paneFrames.compactMap { paneId, paneFrame -> (UUID, CGRect)? in
            paneFrame.contains(location) ? (paneId, paneFrame) : nil
        }
        guard !containingPanes.isEmpty else { return nil }

        // Deterministic tiebreakers are required because dictionary iteration order
        // is not a stable layout order and pane frames can touch/overlap by a few points.
        let selected = containingPanes.min { lhs, rhs in
            let lhsArea = lhs.1.width * lhs.1.height
            let rhsArea = rhs.1.width * rhs.1.height
            if lhsArea != rhsArea {
                return lhsArea < rhsArea
            }
            if lhs.1.minX != rhs.1.minX {
                return lhs.1.minX < rhs.1.minX
            }
            if lhs.1.minY != rhs.1.minY {
                return lhs.1.minY < rhs.1.minY
            }
            return lhs.0.uuidString < rhs.0.uuidString
        }
        guard let (paneId, paneFrame) = selected else { return nil }
        let localPoint = CGPoint(
            x: location.x - paneFrame.minX,
            y: location.y - paneFrame.minY
        )
        let zone = DropZone.calculate(at: localPoint, in: paneFrame.size)

        return PaneDropTarget(paneId: paneId, zone: zone)
    }

    private static func resolveEdgeCorridorTarget(location: CGPoint, paneFrames: [UUID: CGRect]) -> PaneDropTarget? {
        let verticalBounds = paneFrames.values.reduce(
            (minY: CGFloat.greatestFiniteMagnitude, maxY: -CGFloat.greatestFiniteMagnitude)
        ) { partial, frame in
            (
                min(partial.minY, frame.minY),
                max(partial.maxY, frame.maxY)
            )
        }
        guard verticalBounds.minY.isFinite,
            verticalBounds.maxY.isFinite,
            verticalBounds.maxY > verticalBounds.minY
        else {
            return nil
        }

        guard let leftmostPane = paneFrames.min(by: { $0.value.minX < $1.value.minX }),
            let rightmostPane = paneFrames.max(by: { $0.value.maxX < $1.value.maxX })
        else {
            return nil
        }

        let leftCorridor = CGRect(
            x: leftmostPane.value.minX - edgeCorridorWidth,
            y: verticalBounds.minY,
            width: edgeCorridorWidth,
            height: verticalBounds.maxY - verticalBounds.minY
        )
        if leftCorridor.contains(location) {
            return PaneDropTarget(paneId: leftmostPane.key, zone: .left)
        }

        let rightCorridor = CGRect(
            x: rightmostPane.value.maxX,
            y: verticalBounds.minY,
            width: edgeCorridorWidth,
            height: verticalBounds.maxY - verticalBounds.minY
        )
        if rightCorridor.contains(location) {
            return PaneDropTarget(paneId: rightmostPane.key, zone: .right)
        }

        return nil
    }
}
