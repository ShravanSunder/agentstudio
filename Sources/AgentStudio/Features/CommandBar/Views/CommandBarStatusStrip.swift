import SwiftUI

// MARK: - CommandBarStatusStrip

/// Top row of the command bar showing optional management state and current pane context.
struct CommandBarStatusStrip: View {
    let mode: CommandBarAppMode
    let context: WorkspacePaneFocus

    var body: some View {
        HStack {
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
