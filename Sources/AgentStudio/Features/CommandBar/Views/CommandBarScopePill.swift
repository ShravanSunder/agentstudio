import SwiftUI

// MARK: - CommandBarScopePill

/// Accent-tinted scope indicator shown when navigated into a nested level.
/// Displays a single label (scope or title) with a dismiss button.
struct CommandBarScopePill: View {
    let label: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .foregroundStyle(.primary.opacity(AppStyles.CommandBar.Rows.scopePillTextOpacity))
                .lineLimit(1)

            Button(action: onDismiss) {
                Text(" ⊗")
                    .foregroundStyle(.primary.opacity(AppStyles.CommandBar.Rows.scopePillDismissOpacity))
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: AppStyles.CommandBar.Rows.scopePillFontSize, weight: .medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(AppStyles.General.Fill.selected))
        )
    }
}
