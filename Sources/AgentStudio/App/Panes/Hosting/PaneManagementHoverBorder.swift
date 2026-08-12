import AgentStudioInfrastructure
import AppKit
import SwiftUI

struct PaneManagementHoverBorder: ViewModifier {
    let paneHost: PaneHostView
    let isManagementLayerActive: Bool
    let isSplitResizing: Bool
    let suppressMainPaneManagementInteraction: Bool

    @State private var isHovered: Bool = false

    private var isManagementHovered: Bool {
        guard !suppressMainPaneManagementInteraction else { return false }
        return isHovered || isPointerInsidePaneView
    }

    private var isPointerInsidePaneView: Bool {
        guard !suppressMainPaneManagementInteraction else { return false }
        guard isManagementLayerActive else { return false }
        guard let window = paneHost.window else { return false }
        let pointInWindow = window.mouseLocationOutsideOfEventStream
        let pointInPane = paneHost.convert(pointInWindow, from: nil)
        return paneHost.bounds.contains(pointInPane)
    }

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = suppressMainPaneManagementInteraction ? false : $0 }
            .overlay {
                if isManagementLayerActive
                    && isManagementHovered
                    && !isSplitResizing
                    && !suppressMainPaneManagementInteraction
                {
                    RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.panel)
                        .strokeBorder(Color.white.opacity(AppStyles.General.Stroke.visible), lineWidth: 1)
                        .allowsHitTesting(false)
                        .animation(
                            .easeInOut(duration: AppStyles.General.Animation.fast),
                            value: isManagementHovered
                        )
                }
            }
    }
}
