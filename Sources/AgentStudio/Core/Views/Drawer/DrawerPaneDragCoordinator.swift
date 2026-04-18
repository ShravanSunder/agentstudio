import CoreGraphics
import Foundation

struct DrawerPaneDropTarget: Equatable {
    let paneId: UUID
    let zone: DrawerDropZone
}

struct DrawerPaneDragCoordinator {
    static func resolveTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect]
    ) -> DrawerPaneDropTarget? {
        let containingPanes = paneFrames.compactMap { paneId, paneFrame -> (UUID, CGRect)? in
            paneFrame.contains(location) ? (paneId, paneFrame) : nil
        }
        guard !containingPanes.isEmpty else { return nil }

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
        let zone = DrawerDropZone.calculate(at: localPoint, in: paneFrame.size)
        return DrawerPaneDropTarget(paneId: paneId, zone: zone)
    }

    static func resolveLatchedTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        currentTarget: DrawerPaneDropTarget?,
        shouldAcceptDrop: (UUID, DrawerDropZone) -> Bool
    ) -> DrawerPaneDropTarget? {
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
}
