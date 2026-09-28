import AppKit

extension RepoExplorerTableMaterializer {
    var currentTopVisibleAnchor: RepoExplorerTableScrollAnchor? {
        guard let snapshot, !snapshot.rows.isEmpty else { return nil }
        let visibleRect = scrollView.contentView.documentVisibleRect
        let visibleRange = tableView.rows(in: visibleRect)
        guard visibleRange.location != NSNotFound else { return nil }
        var intersectingRows: [(RepoExplorerRowID, CGFloat)] = []
        for rowIndex in visibleRange.location..<NSMaxRange(visibleRange) {
            guard snapshot.rows.indices.contains(rowIndex) else { continue }
            let rowRect = tableView.rect(ofRow: rowIndex)
            guard rowRect.intersects(visibleRect) else { continue }
            intersectingRows.append((snapshot.rows[rowIndex].id, rowRect.minY - visibleRect.minY))
        }
        guard let first = intersectingRows.first else { return nil }
        return RepoExplorerTableScrollAnchor(
            rowID: first.0,
            offset: first.1,
            identity: RepoExplorerRowAnchorIdentity(rowID: first.0),
            followingIdentities: intersectingRows.dropFirst().map {
                RepoExplorerRowAnchorIdentity(rowID: $0.0)
            },
            wasAtTop: visibleRect.minY <= 0
        )
    }
}
