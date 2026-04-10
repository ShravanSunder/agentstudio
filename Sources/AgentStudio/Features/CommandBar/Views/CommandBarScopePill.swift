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
                .foregroundStyle(.primary.opacity(0.60))
                .lineLimit(1)

            Button(action: onDismiss) {
                Text(" ⊗")
                    .foregroundStyle(.primary.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: AppStyle.textSm, weight: .medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
        )
    }
}
