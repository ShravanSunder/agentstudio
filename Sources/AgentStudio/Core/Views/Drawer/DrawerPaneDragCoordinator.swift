import CoreGraphics
import Foundation

struct DrawerPaneDragCoordinator {
    static let creationBandHeight: CGFloat = 28

    static func resolveTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        layout: DrawerGridLayout,
        containerBounds: CGRect
    ) -> DrawerRearrangeTarget? {
        guard
            let target = DropTargetResolver.resolve(
                location: location,
                rows: rowsDictionary(from: layout),
                paneFrames: paneFrames,
                containerBounds: containerBounds,
                config: config(for: layout),
                splittablePanes: []
            )
        else {
            return nil
        }

        return drawerTarget(from: target)
    }

    static func resolveLatchedTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        layout: DrawerGridLayout,
        containerBounds: CGRect,
        currentTarget: DrawerRearrangeTarget?,
        shouldAcceptDrop: (DrawerRearrangeTarget) -> Bool
    ) -> DrawerRearrangeTarget? {
        let rows = rowsDictionary(from: layout)
        let config = config(for: layout)
        let currentDropTarget = currentTarget.map(dropTarget(from:))

        guard
            let target = DropTargetResolver.resolveLatched(
                location: location,
                rows: rows,
                paneFrames: paneFrames,
                containerBounds: containerBounds,
                config: config,
                splittablePanes: [],
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
        paneFrames: [UUID: CGRect],
        layout: DrawerGridLayout,
        containerBounds: CGRect
    ) -> [DrawerRearrangeTarget: CGRect] {
        let rects = DropTargetResolver.targetRects(
            rows: rowsDictionary(from: layout),
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            config: config(for: layout),
            splittablePanes: []
        )

        return rects.reduce(into: [:]) { translatedRects, entry in
            guard let target = drawerTarget(from: entry.key) else { return }
            translatedRects[target] = entry.value
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
        case .paneSlot(let row, let index):
            .rowSlot(row: drawerRow(from: row), insertionIndex: index)
        case .paneNewRow(let position):
            .createSecondRow(position: drawerRow(from: position))
        case .paneSplit:
            nil
        }
    }

    private static func dropTarget(from target: DrawerRearrangeTarget) -> DropTarget {
        switch target {
        case .rowSlot(let row, let insertionIndex):
            .paneSlot(row: rowID(from: row), index: insertionIndex)
        case .createSecondRow(let position):
            .paneNewRow(position: newRowPosition(from: position))
        }
    }

    private static func drawerRow(from row: RowID) -> DrawerRowPlacement {
        row == .drawerBottom ? .bottom : .top
    }

    private static func drawerRow(from position: NewRowPosition) -> DrawerRowPlacement {
        position == .bottom ? .bottom : .top
    }

    private static func rowID(from row: DrawerRowPlacement) -> RowID {
        row == .bottom ? .drawerBottom : .drawerTop
    }

    private static func newRowPosition(from row: DrawerRowPlacement) -> NewRowPosition {
        row == .bottom ? .bottom : .top
    }
}
