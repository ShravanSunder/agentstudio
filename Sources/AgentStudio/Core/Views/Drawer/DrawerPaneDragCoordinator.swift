import CoreGraphics
import Foundation

struct DrawerPaneDragGeometry {
    let paneFrames: [UUID: CGRect]
    let layout: DrawerGridLayout
    let containerBounds: CGRect
    let minimizedPaneIds: Set<UUID>

    var splittablePaneIds: Set<UUID> {
        Set(layout.paneIds).subtracting(minimizedPaneIds)
    }
}

struct DrawerPaneDragCoordinator {
    static let creationBandHeight: CGFloat = 28

    static func resolveTarget(
        location: CGPoint,
        geometry: DrawerPaneDragGeometry
    ) -> DrawerRearrangeTarget? {
        guard
            let target = DropTargetResolver.resolve(
                location: location,
                rows: rowsDictionary(from: geometry.layout),
                paneFrames: geometry.paneFrames,
                containerBounds: geometry.containerBounds,
                config: config(for: geometry.layout),
                splittablePanes: geometry.splittablePaneIds
            )
        else {
            return nil
        }

        return drawerTarget(from: target)
    }

    static func resolveLatchedTarget(
        location: CGPoint,
        geometry: DrawerPaneDragGeometry,
        currentTarget: DrawerRearrangeTarget?,
        shouldAcceptDrop: (DrawerRearrangeTarget) -> Bool
    ) -> DrawerRearrangeTarget? {
        let rows = rowsDictionary(from: geometry.layout)
        let config = config(for: geometry.layout)
        let currentDropTarget = currentTarget.map(dropTarget(from:))

        guard
            let target = DropTargetResolver.resolveLatched(
                location: location,
                rows: rows,
                paneFrames: geometry.paneFrames,
                containerBounds: geometry.containerBounds,
                config: config,
                splittablePanes: geometry.splittablePaneIds,
                currentTarget: currentDropTarget,
                shouldAccept: { target in
                    guard let drawerTarget = drawerTarget(from: target) else { return false }
                    return shouldAcceptDrop(drawerTarget)
                }
            )
        else {
            return nil
        }

        return drawerTarget(from: target)
    }

    static func targetRects(
        geometry: DrawerPaneDragGeometry
    ) -> [DrawerRearrangeTarget: CGRect] {
        let rects = DropTargetResolver.targetRects(
            rows: rowsDictionary(from: geometry.layout),
            paneFrames: geometry.paneFrames,
            containerBounds: geometry.containerBounds,
            config: config(for: geometry.layout),
            splittablePanes: geometry.splittablePaneIds
        )

        return rects.reduce(into: [:]) { translatedRects, entry in
            guard let target = drawerTarget(from: entry.key) else { return }
            translatedRects[target] = entry.value
        }
    }

    static func sizingMode(for target: DrawerRearrangeTarget, isShiftHeld: Bool) -> DropSizingMode {
        if isShiftHeld { return .proportional }

        switch target {
        case .paneSplit:
            return .halveTarget
        case .rowSlot, .createSecondRow:
            return .proportional
        }
    }

    private static func config(for layout: DrawerGridLayout) -> DropTargetConfig {
        layout.bottomRow == nil ? .drawerSingleRow : .drawerTwoRow
    }

    private static func rowsDictionary(from layout: DrawerGridLayout) -> [RowID: [UUID]] {
        var rows: [RowID: [UUID]] = [.drawerTop: layout.topRow.paneIds]
        if let bottomRow = layout.bottomRow {
            rows[.drawerBottom] = bottomRow.paneIds
        }
        return rows
    }

    private static func drawerTarget(from target: DropTarget) -> DrawerRearrangeTarget? {
        switch target {
        case .paneSplit(let paneId, let side):
            return .paneSplit(paneId: paneId, side: side)
        case .paneSlot(let row, let index):
            return .rowSlot(row: drawerRow(from: row), insertionIndex: index)
        case .paneNewRow(let position):
            return .createSecondRow(position: drawerRow(from: position))
        }
    }

    private static func dropTarget(from target: DrawerRearrangeTarget) -> DropTarget {
        switch target {
        case .paneSplit(let paneId, let side):
            .paneSplit(paneId: paneId, side: side)
        case .rowSlot(let row, let insertionIndex):
            .paneSlot(row: rowID(from: row), index: insertionIndex)
        case .createSecondRow(let position):
            .paneNewRow(position: newRowPosition(from: position))
        }
    }

    private static func drawerRow(from row: RowID) -> DrawerRowPlacement {
        switch row {
        case .drawerTop:
            return .top
        case .drawerBottom:
            return .bottom
        case .main:
            assertionFailure("Drawer target mapping received non-drawer row")
            return .top
        }
    }

    private static func drawerRow(from position: NewRowPosition) -> DrawerRowPlacement {
        switch position {
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }

    private static func rowID(from row: DrawerRowPlacement) -> RowID {
        switch row {
        case .top:
            return .drawerTop
        case .bottom:
            return .drawerBottom
        }
    }

    private static func newRowPosition(from row: DrawerRowPlacement) -> NewRowPosition {
        switch row {
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }
}
