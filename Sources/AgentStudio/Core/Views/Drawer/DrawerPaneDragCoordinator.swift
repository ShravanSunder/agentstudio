import CoreGraphics
import Foundation

struct DrawerPaneDragCoordinator {
    static let creationBandHeight: CGFloat = 28
    private static let slotMarkerWidth: CGFloat = 10

    static func resolveTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        layout: DrawerGridLayout,
        containerBounds: CGRect
    ) -> DrawerRearrangeTarget? {
        guard !paneFrames.isEmpty else { return nil }

        if layout.bottomRow == nil {
            let topBand = CGRect(
                x: containerBounds.minX,
                y: containerBounds.minY,
                width: containerBounds.width,
                height: creationBandHeight
            )
            if topBand.contains(location) {
                return .createSecondRow(position: .top)
            }

            let bottomBand = CGRect(
                x: containerBounds.minX,
                y: containerBounds.maxY - creationBandHeight,
                width: containerBounds.width,
                height: creationBandHeight
            )
            if bottomBand.contains(location) {
                return .createSecondRow(position: .bottom)
            }

            return resolveRowSlot(
                location: location,
                paneIds: layout.topRow.paneIds,
                row: .top,
                paneFrames: paneFrames
            )
        }

        if let target = resolveRowSlot(
            location: location,
            paneIds: layout.topRow.paneIds,
            row: .top,
            paneFrames: paneFrames
        ) {
            return target
        }

        return resolveRowSlot(
            location: location,
            paneIds: layout.bottomRow?.paneIds ?? [],
            row: .bottom,
            paneFrames: paneFrames
        )
    }

    static func resolveLatchedTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        layout: DrawerGridLayout,
        containerBounds: CGRect,
        currentTarget: DrawerRearrangeTarget?,
        shouldAcceptDrop: (DrawerRearrangeTarget) -> Bool
    ) -> DrawerRearrangeTarget? {
        if let resolvedTarget = resolveTarget(
            location: location,
            paneFrames: paneFrames,
            layout: layout,
            containerBounds: containerBounds
        ),
            shouldAcceptDrop(resolvedTarget)
        {
            return resolvedTarget
        }

        if let currentTarget, shouldAcceptDrop(currentTarget) {
            return currentTarget
        }

        return nil
    }

    static func targetRects(
        paneFrames: [UUID: CGRect],
        layout: DrawerGridLayout,
        containerBounds: CGRect
    ) -> [DrawerRearrangeTarget: CGRect] {
        guard !paneFrames.isEmpty else { return [:] }

        var rects: [DrawerRearrangeTarget: CGRect] = [:]

        if layout.bottomRow == nil {
            rects[.createSecondRow(position: .top)] = CGRect(
                x: containerBounds.minX,
                y: containerBounds.minY,
                width: containerBounds.width,
                height: creationBandHeight
            )
            rects[.createSecondRow(position: .bottom)] = CGRect(
                x: containerBounds.minX,
                y: containerBounds.maxY - creationBandHeight,
                width: containerBounds.width,
                height: creationBandHeight
            )
        }

        mergeSlotRects(
            into: &rects,
            paneIds: layout.topRow.paneIds,
            row: .top,
            paneFrames: paneFrames
        )
        if let bottomPaneIds = layout.bottomRow?.paneIds {
            mergeSlotRects(
                into: &rects,
                paneIds: bottomPaneIds,
                row: .bottom,
                paneFrames: paneFrames
            )
        }

        return rects
    }

    private static func resolveRowSlot(
        location: CGPoint,
        paneIds: [UUID],
        row: DrawerRowPlacement,
        paneFrames: [UUID: CGRect]
    ) -> DrawerRearrangeTarget? {
        let sortedFrames = sortedRowFrames(paneIds: paneIds, paneFrames: paneFrames)
        guard !sortedFrames.isEmpty else { return nil }

        let rowMinY = sortedFrames.map(\.minY).min() ?? 0
        let rowMaxY = sortedFrames.map(\.maxY).max() ?? 0
        guard location.y >= rowMinY, location.y <= rowMaxY else { return nil }

        if location.x <= sortedFrames[0].midX {
            return .rowSlot(row: row, insertionIndex: 0)
        }

        for index in 1..<sortedFrames.count {
            let previousMidX = sortedFrames[index - 1].midX
            let currentMidX = sortedFrames[index].midX
            if location.x > previousMidX, location.x <= currentMidX {
                return .rowSlot(row: row, insertionIndex: index)
            }
        }

        return .rowSlot(row: row, insertionIndex: sortedFrames.count)
    }

    private static func mergeSlotRects(
        into rects: inout [DrawerRearrangeTarget: CGRect],
        paneIds: [UUID],
        row: DrawerRowPlacement,
        paneFrames: [UUID: CGRect]
    ) {
        let sortedFrames = sortedRowFrames(paneIds: paneIds, paneFrames: paneFrames)
        guard !sortedFrames.isEmpty else { return }

        let rowMinY = sortedFrames.map(\.minY).min() ?? 0
        let rowMaxY = sortedFrames.map(\.maxY).max() ?? 0
        let markerHalfWidth = slotMarkerWidth / 2

        for insertionIndex in 0...sortedFrames.count {
            let boundaryX: CGFloat
            if insertionIndex == 0 {
                boundaryX = sortedFrames[0].minX
            } else if insertionIndex == sortedFrames.count {
                boundaryX = sortedFrames[sortedFrames.count - 1].maxX
            } else {
                boundaryX = (sortedFrames[insertionIndex - 1].midX + sortedFrames[insertionIndex].midX) / 2
            }

            rects[.rowSlot(row: row, insertionIndex: insertionIndex)] = CGRect(
                x: boundaryX - markerHalfWidth,
                y: rowMinY,
                width: slotMarkerWidth,
                height: rowMaxY - rowMinY
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
