import SwiftUI

struct SidebarRepoGroupHeader<TrailingContent: View>: View {
    let isCollapsed: Bool
    let icon: SidebarSourceGroupIcon
    let repoTitle: String
    let organizationName: String?
    let onToggle: () -> Void
    @ViewBuilder let trailingContent: () -> TrailingContent

    static var chromePolicy: SidebarHeaderChromePolicy {
        SidebarSourceGroupHeader<TrailingContent>.chromePolicy
    }

    static var leadingInset: CGFloat {
        SidebarSourceGroupHeader<TrailingContent>.leadingInset
    }

    init(
        isCollapsed: Bool,
        icon: SidebarSourceGroupIcon = .repo,
        repoTitle: String,
        organizationName: String?,
        onToggle: @escaping () -> Void,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent
    ) {
        self.isCollapsed = isCollapsed
        self.icon = icon
        self.repoTitle = repoTitle
        self.organizationName = organizationName
        self.onToggle = onToggle
        self.trailingContent = trailingContent
    }

    var body: some View {
        SidebarSourceGroupHeader(
            isCollapsed: isCollapsed,
            icon: icon,
            title: repoTitle,
            secondaryTitle: organizationName,
            accessibilityIdentifier: nil,
            onToggle: onToggle
        ) {
            trailingContent()
        }
    }
}

extension SidebarRepoGroupHeader where TrailingContent == EmptyView {
    init(
        isCollapsed: Bool,
        icon: SidebarSourceGroupIcon = .repo,
        repoTitle: String,
        organizationName: String?,
        onToggle: @escaping () -> Void
    ) {
        self.isCollapsed = isCollapsed
        self.icon = icon
        self.repoTitle = repoTitle
        self.organizationName = organizationName
        self.onToggle = onToggle
        self.trailingContent = { EmptyView() }
    }
}
