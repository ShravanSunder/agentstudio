import SwiftUI

struct SidebarSourceGroupHeader<TrailingContent: View>: View {
    let isCollapsed: Bool
    let icon: AppEntityIcon
    let title: String
    let secondaryTitle: String?
    let accessibilityIdentifier: String?
    let onToggle: () -> Void
    @ViewBuilder let trailingContent: () -> TrailingContent

    static var chromePolicy: SidebarHeaderChromePolicy {
        .sourceGroupHeader
    }

    static var leadingInset: CGFloat {
        AppStyles.Shell.Sidebar.listRowLeadingInset
    }

    var body: some View {
        Button(action: onToggle) {
            SidebarSectionHeaderRow(isCollapsed: isCollapsed) {
                HStack(spacing: AppStyles.Shell.Sidebar.groupIconTitleSpacing) {
                    headerIcon
                        .frame(
                            width: AppStyles.Shell.Sidebar.groupIconColumnWidth,
                            alignment: .leading
                        )

                    HStack(spacing: AppStyles.Shell.Sidebar.groupTitleSpacing) {
                        Text(title)
                            .font(.system(size: AppStyles.General.Typography.textLg, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(2)

                        if let secondaryTitle, !secondaryTitle.isEmpty {
                            Text("·")
                                .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Text(secondaryTitle)
                                .font(
                                    .system(
                                        size: AppStyles.Shell.Sidebar.groupOrganizationFontSize,
                                        weight: .medium
                                    )
                                )
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(
                                    maxWidth: AppStyles.Shell.Sidebar.groupOrganizationMaxWidth,
                                    alignment: .leading
                                )
                                .layoutPriority(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, AppStyles.Shell.Sidebar.groupRowVerticalPadding)
                .contentShape(Rectangle())
            } trailingContent: {
                trailingContent()
            }
            .padding(.leading, Self.leadingInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .modifier(OptionalAccessibilityIdentifier(identifier: accessibilityIdentifier))
    }

    private var accessibilityLabel: String {
        guard let secondaryTitle, !secondaryTitle.isEmpty else { return title }
        return "\(title), \(secondaryTitle)"
    }

    @ViewBuilder
    private var headerIcon: some View {
        icon.swiftUIImage(size: AppStyles.Shell.Sidebar.groupIconSize)
    }
}

extension SidebarSourceGroupHeader where TrailingContent == EmptyView {
    init(
        isCollapsed: Bool,
        icon: AppEntityIcon,
        title: String,
        secondaryTitle: String?,
        accessibilityIdentifier: String? = nil,
        onToggle: @escaping () -> Void
    ) {
        self.isCollapsed = isCollapsed
        self.icon = icon
        self.title = title
        self.secondaryTitle = secondaryTitle
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onToggle = onToggle
        self.trailingContent = { EmptyView() }
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
