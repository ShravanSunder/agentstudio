import SwiftUI

// MARK: - CommandBarStatusStrip

/// Top row of the command bar showing optional management state and current pane context.
struct CommandBarStatusStrip: View {
    let mode: CommandBarAppMode
    let context: WorkspacePaneFocus
    let scopeLabel: String

    init(
        mode: CommandBarAppMode,
        context: WorkspacePaneFocus,
        scopeLabel: String = "Main"
    ) {
        self.mode = mode
        self.context = context
        self.scopeLabel = scopeLabel
    }

    var body: some View {
        HStack {
            Text(scopeLabel)
                .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                .foregroundStyle(.primary.opacity(AppStyles.CommandBar.Rows.statusContextOpacity))
                .lineLimit(1)
                .accessibilityHidden(true)
                .background(
                    AccessibilityLabelBridge(
                        identifier: "commandBarScopeIdentity",
                        label: "Current Command Bar scope, \(scopeLabel)"
                    )
                )

            if let icon = mode.statusStripIcon, let label = mode.statusStripLabel {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                    Text(label)
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
            }

            Spacer()

            if let icon = context.icon, let label = context.label {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                    Text(label)
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                }
                .foregroundStyle(.primary.opacity(AppStyles.CommandBar.Rows.statusContextOpacity))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
}
