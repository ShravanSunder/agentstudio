import SwiftUI

// MARK: - CommandBarBreadcrumbRow

/// The single nested-navigation trail. Ancestors are clickable; the current
/// level is presented as non-interactive context.
struct CommandBarBreadcrumbRow: View {
    let labels: [String]
    let onNavigate: @MainActor @Sendable (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                if index < labels.count - 1 {
                    Button(label) {
                        onNavigate(index)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: AppStyles.General.Typography.textSm))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                    .accessibilityIdentifier("commandBarBreadcrumb.\(index)")
                    .accessibilityLabel("Navigate to \(label)")
                    .accessibilityHint("Return to this Command Bar level")
                    .accessibilityHidden(true)
                    .background(
                        AccessibilityPressBridge(
                            identifier: "commandBarBreadcrumb.\(index)",
                            label: "Navigate to \(label)",
                            help: "Return to this Command Bar level",
                            action: { onNavigate(index) }
                        )
                    )
                } else {
                    Text(label)
                        .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.opacity(0.06))
    }
}
