import CoreGraphics
import Foundation

struct NewRowBandConfig: Hashable, Sendable {
    let bandHeight: CGFloat
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
        newRowBand: .init(bandHeight: 28),
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
