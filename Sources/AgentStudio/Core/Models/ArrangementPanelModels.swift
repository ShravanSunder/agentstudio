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

/// Pure decision for auto-opening the arrangement popover when a rename
/// starts from outside the popover (e.g. via the command palette). Targets
/// only renames whose arrangement belongs to the currently active tab,
/// and only when the popover is not already presented.
enum ArrangementPopoverAutoOpen {
    static func shouldOpen(
        editingArrangementId: UUID?,
        activeTabArrangements: [ArrangementInfo]?,
        isPresented: Bool
    ) -> Bool {
        guard let editingArrangementId,
            let activeTabArrangements,
            activeTabArrangements.contains(where: { $0.id == editingArrangementId }),
            !isPresented
        else { return false }
        return true
    }
}

/// Pure decision for whether a chip in the popover shows the rename pencil.
/// Default arrangements are not renameable, so the affordance is hidden.
enum ArrangementChipAffordance {
    static func showsRenamePencil(isDefault: Bool) -> Bool {
        !isDefault
    }
}

struct ArrangementChipVisualStyle: Equatable {
    let isActive: Bool
    let isHovered: Bool
    let isPressed: Bool

    var backgroundOpacity: CGFloat {
        if isPressed {
            return AppStyle.fillPressed
        }
        if isActive {
            return AppStyle.fillActive
        }
        if isHovered {
            return AppStyle.fillHover
        }
        return AppStyle.fillSubtle
    }

    var foregroundIsPrimary: Bool {
        isActive || isHovered || isPressed
    }
}
