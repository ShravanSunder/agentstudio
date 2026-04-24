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

            if config.allowsPaneSplit,
                let (paneId, frame) = rowFrames.containingFrame(for: location, splittablePanes: splittablePanes)
            {
                let side: DropZoneSide = location.x < frame.midX ? .left : .right
                return .paneSplit(paneId: paneId, side: side)
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
        config: DropTargetConfig
    ) -> [DropTarget: CGRect] {
        var rects: [DropTarget: CGRect] = [:]

        if let band = config.newRowBand {
            rects[.paneNewRow(position: .top)] = CGRect(
                x: containerBounds.minX,
                y: containerBounds.minY,
                width: containerBounds.width,
                height: band.bandHeight
            )
            rects[.paneNewRow(position: .bottom)] = CGRect(
                x: containerBounds.minX,
                y: containerBounds.maxY - band.bandHeight,
                width: containerBounds.width,
                height: band.bandHeight
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

            for (index, rect) in rowFrames.slotRects().enumerated() {
                rects[.paneSlot(row: rowID, index: index)] = rect
            }
        }

        return rects
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

        let topBand = CGRect(
            x: containerBounds.minX,
            y: containerBounds.minY,
            width: containerBounds.width,
            height: band.bandHeight
        )
        if topBand.contains(location) {
            return .paneNewRow(position: .top)
        }

        let bottomBand = CGRect(
            x: containerBounds.minX,
            y: containerBounds.maxY - band.bandHeight,
            width: containerBounds.width,
            height: band.bandHeight
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

    func containingFrame(
        for location: CGPoint,
        splittablePanes: Set<UUID>
    ) -> (paneId: UUID, frame: CGRect)? {
        let containingFrames = values.filter { paneId, frame in
            splittablePanes.contains(paneId) && frame.contains(location)
        }
        guard !containingFrames.isEmpty else { return nil }

        return containingFrames.min { lhs, rhs in
            let lhsArea = lhs.frame.width * lhs.frame.height
            let rhsArea = rhs.frame.width * rhs.frame.height
            if lhsArea != rhsArea {
                return lhsArea < rhsArea
            }
            if lhs.frame.minX != rhs.frame.minX {
                return lhs.frame.minX < rhs.frame.minX
            }
            if lhs.frame.minY != rhs.frame.minY {
                return lhs.frame.minY < rhs.frame.minY
            }
            return lhs.paneId.uuidString < rhs.paneId.uuidString
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

    func slotRects() -> [CGRect] {
        var boundaries: [CGFloat] = [first.frame.minX, first.frame.midX]

        if values.count > 1 {
            for index in 1..<(values.count - 1) {
                boundaries.append(values[index].frame.midX)
            }
            boundaries.append(last.frame.midX)
        }
        boundaries.append(last.frame.maxX)

        return (0...values.count).map { index in
            CGRect(
                x: boundaries[index],
                y: minY,
                width: max(boundaries[index + 1] - boundaries[index], 1),
                height: maxY - minY
            )
        }
    }
}
