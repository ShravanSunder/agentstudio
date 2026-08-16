import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

// MARK: - CommandBarBreadcrumbRow

/// The single nested-navigation trail. Ancestors are clickable; the current
/// level is presented as non-interactive context.
struct CommandBarBreadcrumbRow: View {
    let items: [CommandBarBreadcrumbItem]
    let octiconLoader: OcticonLoader
    let onNavigate: @MainActor @Sendable (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                if index < items.count - 1 {
                    Button {
                        onNavigate(index)
                    } label: {
                        breadcrumbContent(item: item, isCurrent: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("commandBarBreadcrumb.\(index)")
                    .accessibilityLabel("Navigate to \(item.accessibilityLabel)")
                    .accessibilityHint("Return to this Command Bar level")
                    .accessibilityHidden(true)
                    .background(
                        AccessibilityPressBridge(
                            identifier: "commandBarBreadcrumb.\(index)",
                            label: "Navigate to \(item.accessibilityLabel)",
                            help: "Return to this Command Bar level",
                            action: { onNavigate(index) }
                        )
                    )
                } else {
                    breadcrumbContent(item: item, isCurrent: true)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(AppStyles.General.Accent.primaryColor.opacity(0.06))
    }

    private func breadcrumbContent(
        item: CommandBarBreadcrumbItem,
        isCurrent: Bool
    ) -> some View {
        HStack(spacing: 4) {
            if let icon = item.icon {
                icon.swiftUIImage(
                    loader: octiconLoader,
                    size: AppStyles.General.Typography.textSm
                )
                .accessibilityHidden(true)
            }

            if isCurrent {
                Text(item.label)
                    .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                    .foregroundStyle(.tertiary)
            } else {
                Text(item.label)
                    .font(.system(size: AppStyles.General.Typography.textSm))
                    .foregroundStyle(AppStyles.General.Accent.primaryColor.opacity(0.8))
            }
        }
        .lineLimit(1)
        .layoutPriority(isCurrent ? 1 : 0)
    }
}
