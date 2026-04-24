import CoreGraphics
import Foundation

struct DrawerPaneDragGeometry {
    let paneFrames: [UUID: CGRect]
    let layout: DrawerGridLayout
    let containerBounds: CGRect
    let minimizedPaneIds: Set<UUID>
    let excludedPaneIds: Set<UUID>

    var splittablePaneIds: Set<UUID> {
        Set(layout.paneIds)
            .subtracting(minimizedPaneIds)
            .subtracting(excludedPaneIds)
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
        targetVisuals(geometry: geometry).mapValues(\.rect)
    }

    static func targetVisuals(
        geometry: DrawerPaneDragGeometry
    ) -> [DrawerRearrangeTarget: DrawerDropTargetVisual] {
        let sharedRects = DropTargetResolver.targetRects(
            rows: rowsDictionary(from: geometry.layout),
            paneFrames: geometry.paneFrames,
            containerBounds: geometry.containerBounds,
            config: config(for: geometry.layout),
            splittablePanes: geometry.splittablePaneIds
        )

        var visuals = sharedRects.reduce(
            into: [DrawerRearrangeTarget: DrawerDropTargetVisual]()
        ) { translatedVisuals, entry in
            guard let target = drawerTarget(from: entry.key) else { return }
            translatedVisuals[target] = DrawerDropTargetVisual.region(entry.value)
        }
        mergeRowSlotMarkers(
            into: &visuals,
            paneIds: geometry.layout.topRow.paneIds,
            row: .top,
            paneFrames: geometry.paneFrames
        )
        if let bottomRow = geometry.layout.bottomRow {
            mergeRowSlotMarkers(
                into: &visuals,
                paneIds: bottomRow.paneIds,
                row: .bottom,
                paneFrames: geometry.paneFrames
            )
        }
        return visuals
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
            guard let row = drawerRow(from: row) else { return nil }
            return .rowSlot(row: row, insertionIndex: index)
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

    private static func drawerRow(from row: RowID) -> DrawerRowPlacement? {
        switch row {
        case .drawerTop:
            return .top
        case .drawerBottom:
            return .bottom
        case .main:
            assertionFailure("Drawer target mapping received non-drawer row")
            return nil
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

    private static func mergeRowSlotMarkers(
        into visuals: inout [DrawerRearrangeTarget: DrawerDropTargetVisual],
        paneIds: [UUID],
        row: DrawerRowPlacement,
        paneFrames: [UUID: CGRect]
    ) {
        let rowFrames = sortedRowFrames(paneIds: paneIds, paneFrames: paneFrames)
        guard !rowFrames.isEmpty else { return }

        let markerWidth = AppStyles.General.Layout.dropTargetMarkerWidth
        let markerHalfWidth = markerWidth / 2
        let rowMinY = rowFrames.map(\.minY).min() ?? 0
        let rowMaxY = rowFrames.map(\.maxY).max() ?? 0

        for insertionIndex in 0...rowFrames.count {
            let boundaryX: CGFloat
            if insertionIndex == 0 {
                boundaryX = rowFrames[0].minX
            } else if insertionIndex == rowFrames.count {
                boundaryX = rowFrames[rowFrames.count - 1].maxX
            } else {
                boundaryX = (rowFrames[insertionIndex - 1].maxX + rowFrames[insertionIndex].minX) / 2
            }

            visuals[.rowSlot(row: row, insertionIndex: insertionIndex)] = .insertionMarker(
                CGRect(
                    x: boundaryX - markerHalfWidth,
                    y: rowMinY,
                    width: markerWidth,
                    height: rowMaxY - rowMinY
                )
            )
        }
    }

    private static func sortedRowFrames(
        paneIds: [UUID],
        paneFrames: [UUID: CGRect]
    ) -> [CGRect] {
        paneIds.compactMap { paneFrames[$0] }.sorted { $0.minX < $1.minX }
    }
}
