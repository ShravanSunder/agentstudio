import CoreGraphics
import Foundation

enum DropTargetResolver {
    static func resolve(
        location: CGPoint,
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig,
        splittablePanes: Set<UUID>
    ) -> DropTarget? {
        if let bandTarget = newRowBandTarget(
            location: location,
            containerBounds: containerBounds,
            config: config
        ) {
            return bandTarget
        }

        for rowID in config.rows {
            guard
                let rowFrames = sortedFrames(
                    rowID: rowID,
                    rows: rows,
                    paneFrames: paneFrames
                )
            else { continue }
            guard rowFrames.containsVertically(location) else { continue }

            if let inPaneTarget = rowFrames.zoneTarget(
                rowID: rowID,
                location: location,
                config: config,
                splittablePanes: splittablePanes,
                sideZoneFloor: AppPolicies.DragAndDrop.paneRowSideZoneFloor
            ) {
                return inPaneTarget
            }

            if let slotIndex = rowFrames.slotIndex(for: location.x, horizontalMaxX: containerBounds.maxX) {
                return .paneSlot(row: rowID, index: slotIndex)
            }
        }

        return corridorTarget(
            location: location,
            rows: rows,
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            config: config
        )
    }

    static func targetRects(
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig,
        splittablePanes: Set<UUID>
    ) -> [DropTarget: CGRect] {
        targetVisuals(
            rows: rows,
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            config: config,
            splittablePanes: splittablePanes
        ).mapValues(\.region)
    }

    static func targetVisuals(
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig,
        splittablePanes: Set<UUID>
    ) -> [DropTarget: DropTargetVisual] {
        var visuals: [DropTarget: DropTargetVisual] = [:]

        if let band = config.newRowBand {
            let bandHeight = band.bandHeight(in: containerBounds)
            visuals[.paneNewRow(position: .top)] = .region(
                CGRect(
                    x: containerBounds.minX,
                    y: containerBounds.minY,
                    width: containerBounds.width,
                    height: bandHeight
                )
            )
            visuals[.paneNewRow(position: .bottom)] = .region(
                CGRect(
                    x: containerBounds.minX,
                    y: containerBounds.maxY - bandHeight,
                    width: containerBounds.width,
                    height: bandHeight
                )
            )
        }

        for rowID in config.rows {
            guard
                let rowFrames = sortedFrames(
                    rowID: rowID,
                    rows: rows,
                    paneFrames: paneFrames
                )
            else { continue }

            let slotVisuals = rowFrames.slotVisuals(
                sideZoneFloor: AppPolicies.DragAndDrop.paneRowSideZoneFloor,
                markerWidth: AppStyles.General.Layout.dropTargetMarkerWidth
            )
            for (index, visual) in slotVisuals.enumerated() {
                visuals[.paneSlot(row: rowID, index: index)] = visual
            }
        }

        if config.allowsPaneSplit {
            for paneId in splittablePanes {
                guard let paneFrame = paneFrames[paneId] else { continue }
                visuals[.paneSplit(paneId: paneId, side: .left)] = .region(
                    CGRect(
                        x: paneFrame.minX,
                        y: paneFrame.minY,
                        width: paneFrame.width / 2,
                        height: paneFrame.height
                    )
                )
                visuals[.paneSplit(paneId: paneId, side: .right)] = .region(
                    CGRect(
                        x: paneFrame.midX,
                        y: paneFrame.minY,
                        width: paneFrame.width / 2,
                        height: paneFrame.height
                    )
                )
            }
        }

        return visuals
    }

    // The pure resolver keeps these inputs explicit because each is an independent geometry constraint.
    // swiftlint:disable:next function_parameter_count
    static func resolveLatched(
        location: CGPoint,
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig,
        splittablePanes: Set<UUID>,
        currentTarget: DropTarget?,
        shouldAccept: (DropTarget) -> Bool
    ) -> DropTarget? {
        if let resolved = resolve(
            location: location,
            rows: rows,
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            config: config,
            splittablePanes: splittablePanes
        ), shouldAccept(resolved) {
            return resolved
        }
        if let currentTarget, shouldAccept(currentTarget) {
            return currentTarget
        }
        return nil
    }

    private static func newRowBandTarget(
        location: CGPoint,
        containerBounds: CGRect,
        config: DropTargetConfig
    ) -> DropTarget? {
        guard let band = config.newRowBand else { return nil }
        let bandHeight = band.bandHeight(in: containerBounds)

        let topBand = CGRect(
            x: containerBounds.minX,
            y: containerBounds.minY,
            width: containerBounds.width,
            height: bandHeight
        )
        if topBand.contains(location) {
            return .paneNewRow(position: .top)
        }

        let bottomBand = CGRect(
            x: containerBounds.minX,
            y: containerBounds.maxY - bandHeight,
            width: containerBounds.width,
            height: bandHeight
        )
        if bottomBand.contains(location) {
            return .paneNewRow(position: .bottom)
        }

        return nil
    }

    private static func corridorTarget(
        location: CGPoint,
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig
    ) -> DropTarget? {
        guard config.edgeCorridorWidth > 0 else { return nil }

        for rowID in config.rows {
            guard
                let rowFrames = sortedFrames(
                    rowID: rowID,
                    rows: rows,
                    paneFrames: paneFrames
                )
            else { continue }
            guard rowFrames.containsVertically(location) else { continue }

            let leftMinX = max(containerBounds.minX, rowFrames.first.frame.minX - config.edgeCorridorWidth)
            let leftMaxX = rowFrames.first.frame.minX
            if leftMaxX > leftMinX,
                CGRect(
                    x: leftMinX,
                    y: rowFrames.minY,
                    width: leftMaxX - leftMinX,
                    height: rowFrames.maxY - rowFrames.minY
                ).contains(location)
            {
                return .paneSlot(row: rowID, index: 0)
            }

            let rightMinX = rowFrames.last.frame.maxX
            let rightMaxX = min(containerBounds.maxX, rightMinX + config.edgeCorridorWidth)
            if rightMaxX > rightMinX,
                CGRect(
                    x: rightMinX,
                    y: rowFrames.minY,
                    width: rightMaxX - rightMinX,
                    height: rowFrames.maxY - rowFrames.minY
                ).contains(location)
            {
                return .paneSlot(row: rowID, index: rowFrames.count)
            }
        }

        return nil
    }

    private static func sortedFrames(
        rowID: RowID,
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect]
    ) -> RowFrames? {
        guard let paneIds = rows[rowID], !paneIds.isEmpty else { return nil }

        let values =
            paneIds
            .compactMap { paneId -> (paneId: UUID, frame: CGRect)? in
                guard let frame = paneFrames[paneId] else { return nil }
                return (paneId, frame)
            }
            .sorted { $0.frame.minX < $1.frame.minX }

        guard !values.isEmpty else { return nil }
        return RowFrames(values: values)
    }
}

private struct RowFrames {
    let values: [(paneId: UUID, frame: CGRect)]

    var count: Int { values.count }
    var first: (paneId: UUID, frame: CGRect) { values[0] }
    var last: (paneId: UUID, frame: CGRect) { values[values.index(before: values.endIndex)] }
    var minY: CGFloat { values.map(\.frame.minY).min() ?? 0 }
    var maxY: CGFloat { values.map(\.frame.maxY).max() ?? 0 }

    func containsVertically(_ location: CGPoint) -> Bool {
        location.y >= minY && location.y <= maxY
    }

    /// Resolve the drop target for a cursor inside one of the panes
    /// in this row, using the 1/4 + 1/2 + 1/4 hover-zone model.
    ///
    /// Center 1/2 of a splittable pane → split (with side determined
    /// by which half of the center the cursor is in).  Center 1/2 of
    /// a non-splittable pane → slot (insert before or after the pane
    /// based on which half).  Side 1/4 zones → slot (between with
    /// neighbor, or edge-insert at row edge).
    ///
    /// When pane frames overlap (parent + child publishing distinct
    /// frames during a layout pass), the smallest-area containing
    /// frame wins so the cursor binds to the most specific pane.
    ///
    /// Returns nil when the cursor is not inside any pane in the row.
    func zoneTarget(
        rowID: RowID,
        location: CGPoint,
        config: DropTargetConfig,
        splittablePanes: Set<UUID>,
        sideZoneFloor: CGFloat
    ) -> DropTarget? {
        let candidates =
            values
            .enumerated()
            .filter { $0.element.frame.contains(location) }
        guard let containing = smallestArea(candidates) else { return nil }

        let entry = containing.element
        let zone = entry.frame.hoverZone(forX: location.x, sideZoneFloor: sideZoneFloor)
        switch zone {
        case .left:
            return .paneSlot(row: rowID, index: containing.offset)
        case .right:
            return .paneSlot(row: rowID, index: containing.offset + 1)
        case .center:
            let side: DropZoneSide = location.x < entry.frame.midX ? .left : .right
            if config.allowsPaneSplit && splittablePanes.contains(entry.paneId) {
                return .paneSplit(paneId: entry.paneId, side: side)
            }
            let slotIndex = side == .left ? containing.offset : containing.offset + 1
            return .paneSlot(row: rowID, index: slotIndex)
        }
    }

    private func smallestArea(
        _ candidates: [EnumeratedSequence<[(paneId: UUID, frame: CGRect)]>.Element]
    ) -> EnumeratedSequence<[(paneId: UUID, frame: CGRect)]>.Element? {
        candidates.min { lhs, rhs in
            let lhsArea = lhs.element.frame.width * lhs.element.frame.height
            let rhsArea = rhs.element.frame.width * rhs.element.frame.height
            if lhsArea != rhsArea {
                return lhsArea < rhsArea
            }
            if lhs.element.frame.minX != rhs.element.frame.minX {
                return lhs.element.frame.minX < rhs.element.frame.minX
            }
            return lhs.element.paneId.uuidString < rhs.element.paneId.uuidString
        }
    }

    func slotIndex(for x: CGFloat, horizontalMaxX: CGFloat) -> Int? {
        guard x >= first.frame.minX, x <= horizontalMaxX else { return nil }

        if x <= first.frame.midX {
            return 0
        }

        for index in 1..<values.count
        where
            x > values[index - 1].frame.midX
            && x <= values[index].frame.midX
        {
            return index
        }

        return values.count
    }

    /// Slot hover-zone visuals, matching the resolver's 1/4 + 1/2 +
    /// 1/4 per-pane zone model.
    ///
    ///   ▸ slot 0       region = outer 1/4 of the leftmost pane
    ///                  marker = thin bar at the row left edge
    ///   ▸ slot 1..n-1  region = right 1/4 of pane[i-1] +
    ///                           left 1/4 of pane[i]
    ///                  marker = thin bar at the inter-pane boundary
    ///                           (midpoint of any gap between them)
    ///   ▸ slot n       region = outer 1/4 of the rightmost pane
    ///                  marker = thin bar at the row right edge
    ///
    /// Side-zone widths grow to `sideZoneFloor` on narrow panes (and
    /// cap at half the pane width) so the visible region stays tight
    /// to the user's actual hover zone instead of the old midX-based
    /// half+half rect, which over-shaded pane interiors.
    func slotVisuals(sideZoneFloor: CGFloat, markerWidth: CGFloat) -> [DropTargetVisual] {
        let topY = minY
        let height = maxY - minY

        return (0...values.count).map { slotIndex in
            let zone = slotZoneRect(
                slotIndex: slotIndex,
                topY: topY,
                height: height,
                sideZoneFloor: sideZoneFloor
            )
            let marker = slotMarkerRect(
                slotIndex: slotIndex,
                topY: topY,
                height: height,
                markerWidth: markerWidth
            )
            return .zoneWithMarker(zone: zone, marker: marker)
        }
    }

    private func slotZoneRect(
        slotIndex: Int,
        topY: CGFloat,
        height: CGFloat,
        sideZoneFloor: CGFloat
    ) -> CGRect {
        if slotIndex == 0 {
            let frame = first.frame
            let width = sideWidth(for: frame, floor: sideZoneFloor)
            return CGRect(x: frame.minX, y: topY, width: width, height: height)
        }
        if slotIndex == values.count {
            let frame = last.frame
            let width = sideWidth(for: frame, floor: sideZoneFloor)
            return CGRect(x: frame.maxX - width, y: topY, width: width, height: height)
        }
        // SYMMETRIC clamp around the boundary so the highlight stays
        // visually consistent as the cursor moves between boundaries
        // with differently-sized neighbors. Half-width = max of (the
        // narrower neighbor's natural 1/4, the side-zone floor).
        // Hover hit zones remain per-pane 1/4; only the painted visual
        // snaps. The marker bar pins the actual commit point.
        let leftFrame = values[slotIndex - 1].frame
        let rightFrame = values[slotIndex].frame
        let leftNatural = leftFrame.width / 4
        let rightNatural = rightFrame.width / 4
        let halfWidth = max(min(leftNatural, rightNatural), sideZoneFloor)
        let boundaryX = (leftFrame.maxX + rightFrame.minX) / 2
        return CGRect(
            x: boundaryX - halfWidth,
            y: topY,
            width: halfWidth * 2,
            height: height
        )
    }

    private func slotMarkerRect(
        slotIndex: Int,
        topY: CGFloat,
        height: CGFloat,
        markerWidth: CGFloat
    ) -> CGRect {
        let boundaryX = slotBoundaryX(slotIndex: slotIndex)
        let halfMarker = markerWidth / 2
        return CGRect(
            x: boundaryX - halfMarker,
            y: topY,
            width: markerWidth,
            height: height
        )
    }

    private func slotBoundaryX(slotIndex: Int) -> CGFloat {
        if slotIndex == 0 { return first.frame.minX }
        if slotIndex == values.count { return last.frame.maxX }
        let leftFrame = values[slotIndex - 1].frame
        let rightFrame = values[slotIndex].frame
        return (leftFrame.maxX + rightFrame.minX) / 2
    }

    private func sideWidth(for frame: CGRect, floor: CGFloat) -> CGFloat {
        let natural = frame.width / 4
        return min(max(natural, floor), frame.width / 2)
    }
}
