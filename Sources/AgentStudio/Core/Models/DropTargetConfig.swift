import CoreGraphics
import Foundation

/// Band region at the top and bottom of a drawer panel that targets
/// "create a new row above/below". Sized as a fraction of the panel
/// height with a minimum-height floor so it stays hittable on short
/// drawers.
struct NewRowBandConfig: Hashable, Sendable {
    /// Fraction of the container height the band should occupy.
    /// 0.2 = top 1/5 and bottom 1/5.
    let heightRatio: CGFloat

    /// Minimum band height regardless of ratio. On short containers
    /// the ratio falls below this; the band stays at this minimum.
    let minHeight: CGFloat

    /// Resolves the band height for a specific container.
    func bandHeight(in container: CGRect) -> CGFloat {
        max(container.height * heightRatio, minHeight)
    }
}

struct DropTargetConfig: Hashable, Sendable {
    let rows: [RowID]
    let newRowBand: NewRowBandConfig?
    let edgeCorridorWidth: CGFloat
    let allowsPaneSplit: Bool

    private init(
        rows: [RowID],
        newRowBand: NewRowBandConfig?,
        edgeCorridorWidth: CGFloat,
        allowsPaneSplit: Bool
    ) {
        self.rows = rows
        self.newRowBand = newRowBand
        self.edgeCorridorWidth = edgeCorridorWidth
        self.allowsPaneSplit = allowsPaneSplit
    }

    static let main = Self(
        rows: [.main],
        newRowBand: nil,
        edgeCorridorWidth: 24,
        allowsPaneSplit: true
    )

    static let drawerSingleRow = Self(
        rows: [.drawerTop],
        newRowBand: NewRowBandConfig(
            heightRatio: AppStyles.General.Layout.drawerNewRowBandRatio,
            minHeight: AppStyles.General.Layout.drawerNewRowBandMinHeight
        ),
        edgeCorridorWidth: 0,
        allowsPaneSplit: true
    )

    static let drawerTwoRow = Self(
        rows: [.drawerTop, .drawerBottom],
        newRowBand: nil,
        edgeCorridorWidth: 0,
        allowsPaneSplit: true
    )
}
