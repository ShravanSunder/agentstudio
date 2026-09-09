import AgentStudioInfrastructure
import SwiftUI

package struct PopoverPanelSectionHeader<Icon: View>: View {
    private let title: String
    private let showsIcon: Bool
    @ViewBuilder private let icon: () -> Icon

    package init(_ title: String, showsIcon: Bool = true, @ViewBuilder icon: @escaping () -> Icon) {
        self.title = title
        self.showsIcon = showsIcon
        self.icon = icon
    }

    package var body: some View {
        HStack(spacing: AppStyles.General.Spacing.standard) {
            if showsIcon {
                icon()
                    .frame(width: AppStyles.General.Icon.compact, height: AppStyles.General.Icon.compact)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                .textCase(.uppercase)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, showsIcon ? AppStyles.General.Spacing.loose : 0)
        .accessibilityAddTraits(.isHeader)
    }
}

extension PopoverPanelSectionHeader where Icon == EmptyView {
    package init(_ title: String) {
        self.init(title, showsIcon: false) { EmptyView() }
    }
}
