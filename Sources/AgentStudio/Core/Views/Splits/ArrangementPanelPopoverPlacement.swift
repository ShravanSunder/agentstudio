import SwiftUI

enum ArrangementPanelPopoverPlacement: Equatable {
    case tabBar
    case minimizedBar

    var sourceAttachmentPoint: UnitPoint {
        .center
    }

    var attachmentAnchor: PopoverAttachmentAnchor {
        .point(sourceAttachmentPoint)
    }

    var arrowEdge: Edge {
        .leading
    }
}
