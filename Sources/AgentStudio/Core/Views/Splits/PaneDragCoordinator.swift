import CoreGraphics
import Foundation

struct PaneDropTarget: Equatable {
    let paneId: UUID
    let zone: DropZone
}

struct PaneDragCoordinator {
    static let edgeCorridorWidth: CGFloat = 24

    static func resolveTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect? = nil
    ) -> PaneDropTarget? {
        if let containedTarget = resolveContainedTarget(location: location, paneFrames: paneFrames) {
            return containedTarget
        }
        return resolveEdgeCorridorTarget(
            location: location,
            paneFrames: paneFrames,
            containerBounds: containerBounds
        )
    }

    static func resolveLatchedTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect? = nil,
        currentTarget: PaneDropTarget?,
        shouldAcceptDrop: (UUID, DropZone) -> Bool
    ) -> PaneDropTarget? {
        if let resolvedTarget = resolveTarget(
            location: location,
            paneFrames: paneFrames,
            containerBounds: containerBounds
        ),
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

    private static func resolveEdgeCorridorTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect?
    ) -> PaneDropTarget? {
        let paneVerticalBounds = paneFrames.values.reduce(
            (minY: CGFloat.greatestFiniteMagnitude, maxY: -CGFloat.greatestFiniteMagnitude)
        ) { partial, frame in
            (
                min(partial.minY, frame.minY),
                max(partial.maxY, frame.maxY)
            )
        }
        guard paneVerticalBounds.minY.isFinite,
            paneVerticalBounds.maxY.isFinite,
            paneVerticalBounds.maxY > paneVerticalBounds.minY
        else {
            return nil
        }

        let verticalMinY =
            if let containerBounds {
                max(paneVerticalBounds.minY, containerBounds.minY)
            } else {
                paneVerticalBounds.minY
            }
        let verticalMaxY =
            if let containerBounds {
                min(paneVerticalBounds.maxY, containerBounds.maxY)
            } else {
                paneVerticalBounds.maxY
            }
        guard verticalMaxY > verticalMinY else { return nil }

        guard let leftmostPane = paneFrames.min(by: { $0.value.minX < $1.value.minX }),
            let rightmostPane = paneFrames.max(by: { $0.value.maxX < $1.value.maxX })
        else {
            return nil
        }

        let leftCorridorMinX =
            if let containerBounds {
                max(containerBounds.minX, leftmostPane.value.minX - edgeCorridorWidth)
            } else {
                leftmostPane.value.minX - edgeCorridorWidth
            }
        let leftCorridorMaxX = leftmostPane.value.minX

        let leftCorridor = CGRect(
            x: leftCorridorMinX,
            y: verticalMinY,
            width: max(leftCorridorMaxX - leftCorridorMinX, 0),
            height: verticalMaxY - verticalMinY
        )
        if leftCorridor.contains(location) {
            return PaneDropTarget(paneId: leftmostPane.key, zone: .left)
        }

        let rightCorridorMinX = rightmostPane.value.maxX
        let rightCorridorMaxX =
            if let containerBounds {
                min(containerBounds.maxX, rightmostPane.value.maxX + edgeCorridorWidth)
            } else {
                rightmostPane.value.maxX + edgeCorridorWidth
            }

        let rightCorridor = CGRect(
            x: rightCorridorMinX,
            y: verticalMinY,
            width: max(rightCorridorMaxX - rightCorridorMinX, 0),
            height: verticalMaxY - verticalMinY
        )
        if rightCorridor.contains(location) {
            return PaneDropTarget(paneId: rightmostPane.key, zone: .right)
        }

        return nil
    }
}
