import Foundation
import SwiftUI

struct PaneVisibilityInfo: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isMinimized: Bool
    let supportsZoom: Bool

    init(
        id: UUID,
        title: String,
        isMinimized: Bool,
        supportsZoom: Bool = false
    ) {
        self.id = id
        self.title = title
        self.isMinimized = isMinimized
        self.supportsZoom = supportsZoom
    }

    var statusSystemImageName: String? {
        isMinimized ? "eye.slash.fill" : nil
    }
}

enum ArrangementPanelRole: Equatable, Sendable {
    case defaultArrangement
    case userLayout
}

struct ArrangementInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let role: ArrangementPanelRole
    let isActive: Bool

    var isDefault: Bool {
        role == .defaultArrangement
    }
}

struct ArrangementPanelZoomSourceIdentity: Equatable, Sendable {
    let title: String
    let detail: String?
    let fullPath: String?
}

struct ArrangementPanelZoomMode: Equatable, Sendable {
    let label: String
    let sourceIdentity: ArrangementPanelZoomSourceIdentity?

    init(
        label: String,
        sourceIdentity: ArrangementPanelZoomSourceIdentity? = nil
    ) {
        self.label = label
        self.sourceIdentity = sourceIdentity
    }
}

struct ArrangementPanelDisplayState: Equatable {
    let visiblePanes: [PaneVisibilityInfo]
    let zoomMode: ArrangementPanelZoomMode?
    let arrangements: [ArrangementInfo]

    var hasVisiblePanes: Bool {
        !visiblePanes.isEmpty
    }

    var allowsArrangementCreation: Bool {
        true
    }

    var showsSaveArrangementButton: Bool {
        hasVisiblePanes
    }

    var showsPaneVisibilitySection: Bool {
        hasVisiblePanes && zoomMode == nil
    }

    var arrangementTriggerLabel: String? {
        zoomMode?.label ?? arrangements.first(where: \.isActive)?.name
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
    static func showsRenamePencil(role: ArrangementPanelRole) -> Bool {
        role == .userLayout
    }
}

struct ArrangementChipVisualStyle: Equatable {
    let isActive: Bool
    let isHovered: Bool
    let isPressed: Bool

    var backgroundOpacity: CGFloat {
        if isPressed {
            return AppStyles.General.Fill.pressed
        }
        if isActive {
            return AppStyles.General.Fill.active
        }
        if isHovered {
            return AppStyles.General.Fill.hover
        }
        return AppStyles.General.Fill.subtle
    }

    var foregroundIsPrimary: Bool {
        isActive || isHovered || isPressed
    }
}
