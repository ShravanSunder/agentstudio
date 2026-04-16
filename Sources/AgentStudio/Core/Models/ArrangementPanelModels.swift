import Foundation
import SwiftUI

struct PaneVisibilityInfo: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isMinimized: Bool
}

struct ArrangementInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isDefault: Bool
    let isActive: Bool
}

struct ArrangementPanelDisplayState: Equatable {
    let visiblePanes: [PaneVisibilityInfo]
    let arrangements: [ArrangementInfo]
    let allowsMinimizedBarToggle: Bool

    var hasVisiblePanes: Bool {
        !visiblePanes.isEmpty
    }

    var showsSaveArrangementButton: Bool {
        hasVisiblePanes
    }

    var showsPaneVisibilitySection: Bool {
        hasVisiblePanes
    }

    var showsMinimizedBarToggle: Bool {
        hasVisiblePanes && allowsMinimizedBarToggle
    }
}

enum ArrangementPanelPopoverPlacement {
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
