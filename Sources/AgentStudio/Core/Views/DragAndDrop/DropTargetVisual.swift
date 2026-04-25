import CoreGraphics
import Foundation

/// Visual representation of a drag drop target.
///
/// Both main and drawer overlays render through this type so the
/// look stays consistent across contexts:
///
///   ▸ `.region(rect)` — soft fill with no border line. Used for
///     splits — the rect is the half of the pane the new pane will
///     land in (per Option B), so the user sees which side wins.
///
///   ▸ `.insertionMarker(rect)` — bright vertical bar. Used for
///     between-pane inserts, edge inserts, and drawer new-row
///     creation bands.
enum DropTargetVisual: Equatable, Sendable {
    case region(CGRect)
    case insertionMarker(CGRect)

    var rect: CGRect {
        switch self {
        case .region(let rect), .insertionMarker(let rect):
            return rect
        }
    }

    var insertionMarkerRect: CGRect? {
        switch self {
        case .insertionMarker(let rect):
            return rect
        case .region:
            return nil
        }
    }
}
