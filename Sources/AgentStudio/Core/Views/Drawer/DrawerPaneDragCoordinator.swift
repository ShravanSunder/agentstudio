import CoreGraphics
import Foundation

struct DrawerPaneDragGeometry {
    let paneFrames: [UUID: CGRect]
    let layout: DrawerGridLayout
    let containerBounds: CGRect
    let minimizedPaneIds: Set<UUID>
    /// Source pane(s) of the active drag. These are excluded from
    /// being splittable AND from being valid drop targets that would
    /// land them at a position equivalent to where they already are
    /// (the universal source-filter rule, R1+R2).
    let excludedPaneIds: Set<UUID>

    var splittablePaneIds: Set<UUID> {
        Set(layout.paneIds)
            .subtracting(minimizedPaneIds)
            .subtracting(excludedPaneIds)
    }
}

/// Source-aware adapter over `DropTargetResolver` for drawer drags.
///
/// In-row source filtering matches the main-pane rule (R1+R2):
///   reject  split(S)
///   reject  slot at S's index
///   reject  slot at S's index + 1
///
/// Drawer-specific rules:
///
///   ▸ R8/R13a — solo row band drop: reject when removing S from its
///     row would leave the row empty (no-op move; drawer collapses
///     back to its current shape).
///
///   ▸ R14 — at-max-rows band drop: when the drawer is at the row
///     hard cap (`AppPolicies.DragAndDrop.drawerMaxRows`), bands are
///     never offered. This is enforced structurally by the config
///     (`drawerTwoRow.newRowBand == nil`).
///
///   ▸ R15/R16 — cross-row drops: foreign targets in the OTHER row
///     remain valid even when S is alone in its own row; the apply
///     path handles row collapse.
struct DrawerPaneDragCoordinator {
    static let creationBandHeight: CGFloat = AppPolicies.DragAndDrop.drawerNewRowBandMinHeight

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

        guard
            let final = applySourceFilter(
                rawTarget: target,
                geometry: geometry,
                cursorLocation: location
            )
        else {
            return nil
        }

        return drawerTarget(from: final)
    }

    static func resolveLatchedTarget(
        location: CGPoint,
        geometry: DrawerPaneDragGeometry,
        currentTarget: DrawerRearrangeTarget?,
        shouldAcceptDrop: (DrawerRearrangeTarget) -> Bool
    ) -> DrawerRearrangeTarget? {
        let rows = rowsDictionary(from: geometry.layout)
        let dropConfig = config(for: geometry.layout)

        let geometricCandidate = DropTargetResolver.resolve(
            location: location,
            rows: rows,
            paneFrames: geometry.paneFrames,
            containerBounds: geometry.containerBounds,
            config: dropConfig,
            splittablePanes: geometry.splittablePaneIds
        )

        if let geometricCandidate {
            // Cursor over a self/adjacent zone → drop the latch
            // (or PROMOTE to split(sibling, side) when cursor is on
            // a foreign sibling pane in the 1/4 zone).
            guard
                let promoted = applySourceFilter(
                    rawTarget: geometricCandidate,
                    geometry: geometry,
                    cursorLocation: location
                )
            else {
                return nil
            }
            guard let drawerTarget = drawerTarget(from: promoted) else {
                return nil
            }
            return shouldAcceptDrop(drawerTarget) ? drawerTarget : nil
        }

        // No geometric candidate → retain currentTarget if still acceptable.
        guard let currentTarget else { return nil }
        let currentDropTarget = dropTarget(from: currentTarget)
        if applySourceFilter(rawTarget: currentDropTarget, geometry: geometry, cursorLocation: location) == nil {
            return nil
        }
        return shouldAcceptDrop(currentTarget) ? currentTarget : nil
    }

    static func targetRects(
        geometry: DrawerPaneDragGeometry
    ) -> [DrawerRearrangeTarget: CGRect] {
        targetVisuals(geometry: geometry).mapValues(\.region)
    }

    static func targetVisuals(
        geometry: DrawerPaneDragGeometry
    ) -> [DrawerRearrangeTarget: DrawerDropTargetVisual] {
        let resolverVisuals = DropTargetResolver.targetVisuals(
            rows: rowsDictionary(from: geometry.layout),
            paneFrames: geometry.paneFrames,
            containerBounds: geometry.containerBounds,
            config: config(for: geometry.layout),
            splittablePanes: geometry.splittablePaneIds
        )

        // For visuals (no cursor location), keep the simpler bool
        // filter — promotion is cursor-driven and only matters at
        // resolve time. The split visuals for foreign panes are
        // already in the dict and will activate naturally when the
        // promoted target lands on them.
        return resolverVisuals.reduce(
            into: [DrawerRearrangeTarget: DrawerDropTargetVisual]()
        ) { accumulator, entry in
            guard isSourceAcceptableForVisuals(target: entry.key, geometry: geometry) else { return }
            guard let target = drawerTarget(from: entry.key) else { return }
            accumulator[target] = entry.value
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

    /// Resolver-time source filter with sibling promotion (R1, R2,
    /// plus drawer band rules). Returns the final drop target the
    /// drawer should commit, or nil if the cursor is in a dead zone.
    private static func applySourceFilter(
        rawTarget: DropTarget,
        geometry: DrawerPaneDragGeometry,
        cursorLocation: CGPoint
    ) -> DropTarget? {
        guard !geometry.excludedPaneIds.isEmpty else { return rawTarget }
        switch rawTarget {
        case .paneSplit(let paneId, _):
            return geometry.excludedPaneIds.contains(paneId) ? nil : rawTarget
        case .paneSlot(let rowID, let index):
            if isSlotAcceptable(rowID: rowID, index: index, geometry: geometry) {
                return rawTarget
            }
            return promoteAdjacentSlotToSiblingSplit(
                rowID: rowID,
                geometry: geometry,
                cursorLocation: cursorLocation
            )
        case .paneNewRow:
            return isNewRowBandAcceptable(geometry: geometry) ? rawTarget : nil
        }
    }

    /// Visuals-time source filter (no cursor — used when building the
    /// full visuals dict). Drops self/adjacent entries; promotion is
    /// not applied here because the split visuals for foreign panes
    /// are already present in the dict.
    private static func isSourceAcceptableForVisuals(
        target: DropTarget,
        geometry: DrawerPaneDragGeometry
    ) -> Bool {
        guard !geometry.excludedPaneIds.isEmpty else { return true }
        switch target {
        case .paneSplit(let paneId, _):
            return !geometry.excludedPaneIds.contains(paneId)
        case .paneSlot(let row, let index):
            return isSlotAcceptable(rowID: row, index: index, geometry: geometry)
        case .paneNewRow:
            return isNewRowBandAcceptable(geometry: geometry)
        }
    }

    /// Find the foreign sibling pane the cursor is hovering inside,
    /// then build a split target on the side closer to the cursor.
    /// Returns nil for cursor on the source pane, in a corridor with
    /// no containing pane, or over a non-splittable pane.
    ///
    /// Promotion is ROW-SCOPED — it only considers panes in the row
    /// the rejected slot belongs to. Without this scope, transient
    /// layout overlap (resize/animation jitter) where a different-row
    /// pane is geometrically smaller and contains the cursor would let
    /// the target jump rows.
    private static func promoteAdjacentSlotToSiblingSplit(
        rowID: RowID,
        geometry: DrawerPaneDragGeometry,
        cursorLocation: CGPoint
    ) -> DropTarget? {
        let rowPaneIds = Set(rowsDictionary(from: geometry.layout)[rowID] ?? [])
        let containing =
            geometry.paneFrames
            .filter { rowPaneIds.contains($0.key) }
            .filter { $0.value.contains(cursorLocation) }
            .min { lhs, rhs in
                let lhsArea = lhs.value.width * lhs.value.height
                let rhsArea = rhs.value.width * rhs.value.height
                if lhsArea != rhsArea { return lhsArea < rhsArea }
                // Stable tie-break: lexicographic UUID ordering so two
                // equal-area panes don't oscillate by dict iteration.
                return lhs.key.uuidString < rhs.key.uuidString
            }
        guard let containing else { return nil }
        let paneId = containing.key
        let frame = containing.value
        guard geometry.splittablePaneIds.contains(paneId) else { return nil }
        let side: DropZoneSide = cursorLocation.x < frame.midX ? .left : .right
        return .paneSplit(paneId: paneId, side: side)
    }

    /// Slot rejection (R2) operates in the resolver's GEOMETRIC index
    /// space — i.e. the row reduced to the panes that actually have a
    /// frame in `paneFrames` and sorted by `minX`. The resolver's
    /// returned `paneSlot.index` references positions in this list.
    ///
    /// When source has a frame in `paneFrames`: source has a geometric
    /// index, and slot i / slot i+1 around it are no-op moves → reject.
    ///
    /// When source has NO frame in `paneFrames` (e.g. its frame was
    /// suppressed during the drag): the resolver's row already excludes
    /// source, so slot indices are in post-delete space and R2 does
    /// not apply — every slot is a real position change.
    private static func isSlotAcceptable(
        rowID: RowID,
        index: Int,
        geometry: DrawerPaneDragGeometry
    ) -> Bool {
        let geometricRow = geometricRow(rowID: rowID, geometry: geometry)
        for excluded in geometry.excludedPaneIds {
            guard let excludedIndex = geometricRow.firstIndex(of: excluded) else { continue }
            if index == excludedIndex || index == excludedIndex + 1 {
                return false
            }
        }
        return true
    }

    private static func geometricRow(rowID: RowID, geometry: DrawerPaneDragGeometry) -> [UUID] {
        guard let layoutPaneIds = rowsDictionary(from: geometry.layout)[rowID] else { return [] }
        return
            layoutPaneIds
            .compactMap { paneId -> (UUID, CGRect)? in
                guard let frame = geometry.paneFrames[paneId] else { return nil }
                return (paneId, frame)
            }
            .sorted { $0.1.minX < $1.1.minX }
            .map(\.0)
    }

    /// New-row band reject when removing every excluded pane from its
    /// row would leave the row empty. That collapses the band drop to
    /// "the same drawer shape, just relabeled" — a no-op (R8 / R13a).
    private static func isNewRowBandAcceptable(geometry: DrawerPaneDragGeometry) -> Bool {
        let rows = rowsDictionary(from: geometry.layout)
        for excluded in geometry.excludedPaneIds {
            guard let containingRow = rows.first(where: { $0.value.contains(excluded) }) else { continue }
            let siblingsInRow = containingRow.value.filter { $0 != excluded }
            if siblingsInRow.isEmpty {
                return false
            }
        }
        return true
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

}
