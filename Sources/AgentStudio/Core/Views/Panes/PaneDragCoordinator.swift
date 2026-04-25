import CoreGraphics
import Foundation

struct PaneDropTarget: Equatable, Hashable {
    let paneId: UUID
    let zone: DropZoneSide
    let sizingTarget: DropTarget

    // Equality includes sizingTarget so that transitioning between
    // zones that share paneId + zone (e.g. slot 1 between P_a and P_b →
    // split right of P_a) is observed as a state change. SwiftUI
    // bindings dedup on equality; collapsing across sizingTarget froze
    // the overlay visual on the previous zone's render.
}

/// Source-aware adapter over the pure `DropTargetResolver`.
///
/// The resolver is geometry-only — it does not know which pane is the
/// drag source. This adapter wraps the resolver with the universal
/// source-filter rule:
///
///   For source S at index i in the row:
///     reject  split(S)              ──► dropping on self
///     reject  slot i                ──► position immediately before S
///     reject  slot i+1              ──► position immediately after S
///
/// Foreign targets stay valid. The visuals dict mirrors these decisions
/// so the overlay never paints a target the commit path would reject.
///
/// When `sourcePaneId` is `nil`, the adapter passes through raw
/// resolver output unfiltered.
///
/// When `sourcePaneId` is set but not present in `paneFrames` (e.g. a
/// cross-tab drag where source's frame isn't published in this row),
/// R1 + R2 simply don't apply — there's no adjacency to enforce.
/// Cross-CONTAINER rejection (main ↔ drawer) is enforced upstream by
/// the dispatcher's `shouldHandleSplitDragPayload`, never here.
struct PaneDragCoordinator {
    static let edgeCorridorWidth: CGFloat = 24

    static func resolveTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect?,
        minimizedPaneIds: Set<UUID>,
        sourcePaneId: UUID? = nil
    ) -> PaneDropTarget? {
        let sortedPaneIds = sortedPaneIds(from: paneFrames)
        let effectiveBounds = containerBounds ?? derivedBounds(from: paneFrames)
        let splittablePaneIds = Set(paneFrames.keys).subtracting(minimizedPaneIds)

        guard
            let target = DropTargetResolver.resolve(
                location: location,
                rows: [.main: sortedPaneIds],
                paneFrames: paneFrames,
                containerBounds: effectiveBounds,
                config: .main,
                splittablePanes: splittablePaneIds
            )
        else {
            return nil
        }

        guard
            let final = applySourceFilter(
                rawTarget: target,
                sourcePaneId: sourcePaneId,
                sortedPaneIds: sortedPaneIds,
                paneFrames: paneFrames,
                splittablePanes: splittablePaneIds,
                cursorLocation: location
            )
        else {
            return nil
        }

        return paneTarget(from: final, sortedPaneIds: sortedPaneIds)
    }

    // The pure adapter keeps each geometry and sizing input explicit at the drag boundary.
    // swiftlint:disable:next function_parameter_count
    static func resolveLatchedTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect?,
        minimizedPaneIds: Set<UUID>,
        currentTarget: PaneDropTarget?,
        isShiftHeld: Bool,
        sourcePaneId: UUID? = nil,
        shouldAcceptDrop: (UUID, DropZoneSide, DropSizingMode) -> Bool
    ) -> PaneDropTarget? {
        let sortedPaneIds = sortedPaneIds(from: paneFrames)
        let effectiveBounds = containerBounds ?? derivedBounds(from: paneFrames)
        let splittablePaneIds = Set(paneFrames.keys).subtracting(minimizedPaneIds)

        let geometricCandidate = DropTargetResolver.resolve(
            location: location,
            rows: [.main: sortedPaneIds],
            paneFrames: paneFrames,
            containerBounds: effectiveBounds,
            config: .main,
            splittablePanes: splittablePaneIds
        )

        if let geometricCandidate {
            // R5: source filter rejects → drop the latch (do NOT fall
            // through to currentTarget retention). The filter may also
            // PROMOTE an adjacent-slot rejection over a foreign sibling
            // to a split of that sibling, so the 1/4 zone always gives
            // commit feedback when it's over a non-source pane.
            guard
                let promoted = applySourceFilter(
                    rawTarget: geometricCandidate,
                    sourcePaneId: sourcePaneId,
                    sortedPaneIds: sortedPaneIds,
                    paneFrames: paneFrames,
                    splittablePanes: splittablePaneIds,
                    cursorLocation: location
                )
            else {
                return nil
            }
            guard let paneTarget = paneTarget(from: promoted, sortedPaneIds: sortedPaneIds) else {
                return nil
            }
            let sizingMode = DropSizingModeResolver.mode(for: paneTarget.sizingTarget, isShiftHeld: isShiftHeld)
            guard shouldAcceptDrop(paneTarget.paneId, paneTarget.zone, sizingMode) else {
                return nil
            }
            return paneTarget
        }

        // R5: no geometric candidate at all (cursor over empty space) →
        // RETAIN the latch if the held target is still source-acceptable
        // and the policy still accepts it. This preserves "ride through
        // layout jitter" behavior.
        guard let currentTarget else { return nil }
        let currentDropTarget = dropTarget(from: currentTarget, sortedPaneIds: sortedPaneIds)
        if let currentDropTarget,
            applySourceFilter(
                rawTarget: currentDropTarget,
                sourcePaneId: sourcePaneId,
                sortedPaneIds: sortedPaneIds,
                paneFrames: paneFrames,
                splittablePanes: splittablePaneIds,
                cursorLocation: location
            ) == nil
        {
            return nil
        }
        let sizingMode = DropSizingModeResolver.mode(for: currentTarget.sizingTarget, isShiftHeld: isShiftHeld)
        if shouldAcceptDrop(currentTarget.paneId, currentTarget.zone, sizingMode) {
            return currentTarget
        }
        return nil
    }

    /// Visuals dict for every accepted drop target, keyed by sizing
    /// target. Self/adjacent entries are omitted when `sourcePaneId`
    /// is set; the overlay can render the entire dict without gating
    /// (R4 — visuals mirror resolver decisions).
    static func targetVisuals(
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        minimizedPaneIds: Set<UUID>,
        sourcePaneId: UUID? = nil
    ) -> [DropTarget: DropTargetVisual] {
        let sortedPaneIds = sortedPaneIds(from: paneFrames)
        let splittablePaneIds = Set(paneFrames.keys).subtracting(minimizedPaneIds)

        var visuals = DropTargetResolver.targetVisuals(
            rows: [.main: sortedPaneIds],
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            config: .main,
            splittablePanes: splittablePaneIds
        )

        if let sourcePaneId, let sourceIndex = sortedPaneIds.firstIndex(of: sourcePaneId) {
            visuals[.paneSplit(paneId: sourcePaneId, side: .left)] = nil
            visuals[.paneSplit(paneId: sourcePaneId, side: .right)] = nil
            visuals[.paneSlot(row: .main, index: sourceIndex)] = nil
            visuals[.paneSlot(row: .main, index: sourceIndex + 1)] = nil
        }

        return visuals
    }

    /// Resolve the visual for a single active drop target.
    ///
    /// `PaneDropTarget`'s equality is fully-discriminated across
    /// `paneId`, `zone`, AND `sizingTarget` (Issue A — collapsing
    /// `sizingTarget` froze the overlay on cursor transitions
    /// between zones with shared paneId+zone like slot↔split). The
    /// visuals dict is keyed by the discriminated `sizingTarget` so
    /// every distinct target maps to its own painted region.
    static func visual(
        for target: PaneDropTarget,
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        minimizedPaneIds: Set<UUID>,
        sourcePaneId: UUID? = nil
    ) -> DropTargetVisual? {
        let visuals = targetVisuals(
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            minimizedPaneIds: minimizedPaneIds,
            sourcePaneId: sourcePaneId
        )
        return visuals[target.sizingTarget]
    }

    // Universal source-filter rule (R1, R2) with the SIBLING-PROMOTION exception.
    //   - R1 reject (split(S)) → nil, no promotion path.
    //   - R2 reject (slot i or slot i+1):
    //       cursor over a foreign sibling pane in that 1/4 zone →
    //         promote to split(sibling, side) so the user gets commit
    //         feedback near the edge.
    //       cursor over the source pane itself, or in a corridor with
    //         no foreign sibling → nil (dead zone).
    //   - Cross-tab drag (source not in this row) → no R2 to enforce, pass through.
    private static func applySourceFilter(
        rawTarget: DropTarget,
        sourcePaneId: UUID?,
        sortedPaneIds: [UUID],
        paneFrames: [UUID: CGRect],
        splittablePanes: Set<UUID>,
        cursorLocation: CGPoint
    ) -> DropTarget? {
        guard let sourcePaneId else { return rawTarget }
        switch rawTarget {
        case .paneSplit(let paneId, _):
            return paneId == sourcePaneId ? nil : rawTarget
        case .paneSlot(_, let index):
            guard let sourceIndex = sortedPaneIds.firstIndex(of: sourcePaneId) else {
                return rawTarget
            }
            if index != sourceIndex && index != sourceIndex + 1 {
                return rawTarget
            }
            return promoteAdjacentSlotToSiblingSplit(
                sourcePaneId: sourcePaneId,
                paneFrames: paneFrames,
                splittablePanes: splittablePanes,
                cursorLocation: cursorLocation
            )
        case .paneNewRow:
            return rawTarget
        }
    }

    /// Find the foreign sibling pane the cursor is hovering inside,
    /// then build a split target on the side closer to the cursor.
    /// Returns nil when the cursor is over the source pane itself, in
    /// a corridor with no containing pane, or over a non-splittable
    /// (e.g. minimized) pane.
    private static func promoteAdjacentSlotToSiblingSplit(
        sourcePaneId: UUID,
        paneFrames: [UUID: CGRect],
        splittablePanes: Set<UUID>,
        cursorLocation: CGPoint
    ) -> DropTarget? {
        let containing =
            paneFrames
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
        guard paneId != sourcePaneId else { return nil }
        guard splittablePanes.contains(paneId) else { return nil }
        let side: DropZoneSide = cursorLocation.x < frame.midX ? .left : .right
        return .paneSplit(paneId: paneId, side: side)
    }

    private static func sortedPaneIds(from paneFrames: [UUID: CGRect]) -> [UUID] {
        paneFrames.keys.sorted { lhs, rhs in
            guard let lhsFrame = paneFrames[lhs], let rhsFrame = paneFrames[rhs] else {
                return lhs.uuidString < rhs.uuidString
            }
            if lhsFrame.minX != rhsFrame.minX {
                return lhsFrame.minX < rhsFrame.minX
            }
            if lhsFrame.minY != rhsFrame.minY {
                return lhsFrame.minY < rhsFrame.minY
            }
            return lhs.uuidString < rhs.uuidString
        }
    }

    private static func derivedBounds(from frames: [UUID: CGRect]) -> CGRect {
        let minX = frames.values.map(\.minX).min() ?? 0
        let maxX = frames.values.map(\.maxX).max() ?? 0
        let minY = frames.values.map(\.minY).min() ?? 0
        let maxY = frames.values.map(\.maxY).max() ?? 0
        return CGRect(
            x: minX - edgeCorridorWidth,
            y: minY,
            width: maxX - minX + edgeCorridorWidth * 2,
            height: maxY - minY
        )
    }

    private static func paneTarget(from target: DropTarget, sortedPaneIds: [UUID]) -> PaneDropTarget? {
        switch target {
        case .paneSplit(let paneId, let side):
            return PaneDropTarget(paneId: paneId, zone: side, sizingTarget: target)
        case .paneSlot(_, let index):
            return paneTarget(slotIndex: index, sortedPaneIds: sortedPaneIds, sizingTarget: target)
        case .paneNewRow:
            return nil
        }
    }

    private static func paneTarget(
        slotIndex: Int,
        sortedPaneIds: [UUID],
        sizingTarget: DropTarget
    ) -> PaneDropTarget? {
        guard !sortedPaneIds.isEmpty else { return nil }
        if slotIndex <= 0 {
            return PaneDropTarget(paneId: sortedPaneIds[0], zone: .left, sizingTarget: sizingTarget)
        }
        if slotIndex >= sortedPaneIds.count {
            guard let lastPaneId = sortedPaneIds.last else { return nil }
            return PaneDropTarget(paneId: lastPaneId, zone: .right, sizingTarget: sizingTarget)
        }
        return PaneDropTarget(paneId: sortedPaneIds[slotIndex - 1], zone: .right, sizingTarget: sizingTarget)
    }

    private static func dropTarget(from target: PaneDropTarget, sortedPaneIds: [UUID]) -> DropTarget? {
        switch target.sizingTarget {
        case .paneSlot, .paneSplit:
            return target.sizingTarget
        case .paneNewRow:
            break
        }
        guard let index = sortedPaneIds.firstIndex(of: target.paneId) else { return nil }
        switch target.zone {
        case .left:
            return .paneSlot(row: .main, index: index)
        case .right:
            return .paneSlot(row: .main, index: index + 1)
        }
    }

}
