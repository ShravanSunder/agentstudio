import CoreGraphics
import Foundation

/// Transient state of one normal-mode drawer top-edge drag.
///
/// Owned locally by `DrawerPanelOverlay`; never published per sample. Height
/// is the anchor height minus cumulative pointer displacement in the fixed
/// `"tabContainer"` space — never the previous rendered height plus a
/// translation. When a sample lands past a size bound, the anchor rebases to
/// the displayed result so reversing direction moves the edge immediately.
struct DrawerNormalResizeSession: Equatable {
    let ownerPaneId: UUID
    /// Container height the session's pointer and height values are valid for.
    let containerHeight: CGFloat
    private(set) var anchorHeight: CGFloat
    private(set) var anchorPointerY: CGFloat
    private(set) var liveHeight: CGFloat
    /// Set when pointer-up dispatched the commit. The live height keeps
    /// displaying until the owner's committed preference reflects it, so the
    /// asynchronous workspace action cannot flash the previous height.
    private(set) var isAwaitingCommit = false

    init(
        ownerPaneId: UUID,
        containerHeight: CGFloat,
        startHeight: CGFloat,
        startPointerY: CGFloat
    ) {
        self.ownerPaneId = ownerPaneId
        self.containerHeight = containerHeight
        anchorHeight = startHeight
        anchorPointerY = startPointerY
        liveHeight = startHeight
    }

    /// Applies one pointer sample. `displayedHeight` maps a requested height to
    /// the height geometry will actually display (bounds and available space).
    mutating func track(
        pointerY: CGFloat,
        displayedHeight: (_ requestedHeight: CGFloat) -> CGFloat
    ) {
        guard !isAwaitingCommit else { return }
        let requestedHeight = anchorHeight - (pointerY - anchorPointerY)
        let shownHeight = displayedHeight(requestedHeight)
        if shownHeight != requestedHeight {
            anchorHeight = shownHeight
            anchorPointerY = pointerY
        }
        liveHeight = shownHeight
    }

    mutating func markAwaitingCommit() {
        isAwaitingCommit = true
    }

    /// A session applies only to the owner and geometry context it began in.
    func applies(toOwner ownerPaneId: UUID, containerHeight: CGFloat) -> Bool {
        self.ownerPaneId == ownerPaneId && self.containerHeight == containerHeight
    }

    /// Owner-specific ratio committed once when the drag completes.
    var committedHeightRatio: Double? {
        guard containerHeight > 0, liveHeight.isFinite else { return nil }
        return Double(liveHeight / containerHeight)
    }
}
