import AgentStudioInfrastructure
import SwiftUI

package struct SidebarPopoverSectionHeader<Icon: View>: View {
    private let title: String
    @ViewBuilder private let icon: () -> Icon

    package init(_ title: String, @ViewBuilder icon: @escaping () -> Icon) {
        self.title = title
        self.icon = icon
    }

    package var body: some View {
        HStack(spacing: AppStyles.General.Spacing.standard) {
            icon()
                .frame(width: AppStyles.General.Icon.compact, height: AppStyles.General.Icon.compact)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                .textCase(.uppercase)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, AppStyles.General.Spacing.loose)
        .accessibilityAddTraits(.isHeader)
    }
}
