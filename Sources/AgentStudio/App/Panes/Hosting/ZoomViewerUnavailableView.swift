import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

struct ZoomViewerUnavailableView: View {
    static let message = "Not in a watched worktree"

    var body: some View {
        Text(Self.message)
            .font(.system(size: AppStyles.General.Typography.textSm, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .background {
                AccessibilityLabelBridge(
                    identifier: "zoomViewer.unavailable",
                    label: Self.message
                )
            }
    }
}
