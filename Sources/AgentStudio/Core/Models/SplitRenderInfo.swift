import Foundation

/// Pre-computed rendering data for a split tree with minimized panes.
/// Computed in the model layer so views have no minimize logic.
struct SplitRenderInfo {

    /// Per-split rendering data.
    struct SplitInfo {
        /// Adjusted ratio for proportional redistribute (visible weight based).
        let adjustedRatio: Double
        /// Whether the left subtree is entirely minimized.
        let leftFullyMinimized: Bool
        /// Whether the right subtree is entirely minimized.
        let rightFullyMinimized: Bool
        /// Ordered minimized pane IDs from the left subtree (for rendering collapsed bars).
        let leftMinimizedPaneIds: [UUID]
        /// Ordered minimized pane IDs from the right subtree (for rendering collapsed bars).
        let rightMinimizedPaneIds: [UUID]
        /// Visible weight of the left subtree (for reverse ratio conversion during drag).
        let leftVisibleWeight: Double
        /// Visible weight of the right subtree (for reverse ratio conversion during drag).
        let rightVisibleWeight: Double

        /// Convert a render-space ratio back to model-space ratio.
        /// Inverts: adjustedRatio = (L*r)/(L*r + R*(1-r)) → r = (a*R)/(L*(1-a) + a*R)
        func modelRatio(fromRenderRatio renderRatio: Double) -> Double {
            let lw = leftVisibleWeight
            let rw = rightVisibleWeight
            guard lw > 0, rw > 0 else { return renderRatio }
            let denom = lw * (1.0 - renderRatio) + renderRatio * rw
            guard denom > 0 else { return renderRatio }
            return (renderRatio * rw) / denom
        }
    }

    /// Rendering info keyed by split node UUID.
    let splitInfo: [UUID: SplitInfo]

    /// Whether every pane in the tree is minimized.
    let allMinimized: Bool

    /// All minimized pane IDs in tree order (for empty-state bar list).
    let allMinimizedPaneIds: [UUID]

    /// Compute render info from a layout and minimized pane set.
    static func compute(layout: Layout, minimizedPaneIds: Set<UUID>) -> Self {
        guard let root = layout.root else {
            return Self(splitInfo: [:], allMinimized: false, allMinimizedPaneIds: [])
        }

        let allMin = root.isFullyMinimized(minimizedPaneIds: minimizedPaneIds)
        let allMinIds = allMin ? root.orderedMinimizedPaneIds(minimizedPaneIds: minimizedPaneIds) : []

        // If no panes are minimized, no adjustments needed
        guard !minimizedPaneIds.isEmpty else {
            return Self(splitInfo: [:], allMinimized: false, allMinimizedPaneIds: [])
        }

        var info: [UUID: SplitInfo] = [:]
        computeNode(root, minimizedPaneIds: minimizedPaneIds, into: &info)
        return Self(splitInfo: info, allMinimized: allMin, allMinimizedPaneIds: allMinIds)
    }

    private static func computeNode(
        _ node: Layout.Node,
        minimizedPaneIds: Set<UUID>,
        into info: inout [UUID: SplitInfo]
    ) {
        guard case .split(let split) = node else { return }

        let leftFullyMin = split.left.isFullyMinimized(minimizedPaneIds: minimizedPaneIds)
        let rightFullyMin = split.right.isFullyMinimized(minimizedPaneIds: minimizedPaneIds)

        // Compute visible weights for each subtree
        let leftVW = split.left.visibleWeight(minimizedPaneIds: minimizedPaneIds)
        let rightVW = split.right.visibleWeight(minimizedPaneIds: minimizedPaneIds)

        // Compute adjusted ratio
        let adjustedRatio: Double
        if leftFullyMin && rightFullyMin {
            adjustedRatio = split.ratio  // Both minimized, doesn't matter
        } else if leftFullyMin || rightFullyMin {
            adjustedRatio = split.ratio  // One side is bars, other fills rest
        } else {
            // Both sides have visible panes — proportional redistribute.
            // Scale each child's visible weight by the parent's ratio allocation
            // to get effective global weights.
            let scaledLeft = leftVW * split.ratio
            let scaledRight = rightVW * (1.0 - split.ratio)
            let total = scaledLeft + scaledRight
            adjustedRatio = total > 0 ? scaledLeft / total : split.ratio
        }

        let leftMinIds =
            leftFullyMin
            ? split.left.orderedMinimizedPaneIds(minimizedPaneIds: minimizedPaneIds)
            : []
        let rightMinIds =
            rightFullyMin
            ? split.right.orderedMinimizedPaneIds(minimizedPaneIds: minimizedPaneIds)
            : []

        info[split.id] = SplitInfo(
            adjustedRatio: adjustedRatio,
            leftFullyMinimized: leftFullyMin,
            rightFullyMinimized: rightFullyMin,
            leftMinimizedPaneIds: leftMinIds,
            rightMinimizedPaneIds: rightMinIds,
            leftVisibleWeight: leftVW,
            rightVisibleWeight: rightVW
        )

        // Recurse into non-fully-minimized subtrees
        if !leftFullyMin { computeNode(split.left, minimizedPaneIds: minimizedPaneIds, into: &info) }
        if !rightFullyMin { computeNode(split.right, minimizedPaneIds: minimizedPaneIds, into: &info) }
    }
}
