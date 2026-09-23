import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

/// Management-mode control on a Pane Zoom drawer that moves it to the other
/// region. Label, icon, and tooltip project from the side command's catalog
/// spec; activation dispatches that targeted catalog command.
struct ZoomDrawerMoveControl: View {
    static let accessibilityIdentifier = "drawerPanel.moveZoomSide"

    let action: TargetedCommandControlAction
    let octiconLoader: OcticonLoader
    @State private var isHovered = false

    var body: some View {
        Button(action: action.perform) {
            Group {
                switch action.commandSpec.icon {
                case .system(let symbol):
                    Image(systemName: symbol.rawValue)
                        .font(.system(size: AppStyles.Shell.ManagementLayer.actionIconSize, weight: .bold))
                case .octicon(let symbol):
                    OcticonImage(
                        name: symbol.rawValue,
                        size: AppStyles.Shell.ManagementLayer.actionIconSize,
                        loader: octiconLoader
                    )
                }
            }
            .foregroundStyle(.white.opacity(AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: isHovered)))
            .frame(
                width: AppStyles.Shell.ManagementLayer.actionSize,
                height: AppStyles.Shell.ManagementLayer.actionSize
            )
            .background(
                Circle()
                    .fill(Color.black.opacity(AppStyles.Shell.ManagementLayer.backgroundOpacity(isHovered: isHovered)))
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .controlHelp(action.commandSpec.controlTooltipRenderValue())
        .onHover { isHovered = $0 }
        .accessibilityHidden(true)
        .background {
            AccessibilityPressBridge(
                identifier: Self.accessibilityIdentifier,
                label: action.commandSpec.label,
                isEnabled: action.isEnabled,
                action: action.perform
            )
        }
    }
}
