import SwiftUI

// MARK: - CommandBarBackRow

/// Breadcrumb back-row shown at the top of nested results.
/// Shows `‹ label` when a label is provided, bare `‹` when nil.
/// Tinted with the accent color to match the scope pill.
struct CommandBarBackRow: View {
    let label: String?
    let onBack: () -> Void

    var body: some View {
        Button(action: onBack) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                if let label {
                    Text(label)
                        .font(.system(size: AppStyles.General.Typography.textSm, weight: .medium))
                        .lineLimit(1)
                }
                Spacer()
            }
            .foregroundStyle(Color.accentColor.opacity(0.7))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.06))
        }
        .buttonStyle(.plain)
    }
}
