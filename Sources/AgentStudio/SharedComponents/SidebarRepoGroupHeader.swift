import AgentStudioInfrastructure
import SwiftUI

package struct SidebarRepoGroupHeader<TrailingContent: View>: View {
    let isCollapsed: Bool
    let octiconLoader: OcticonLoader
    let icon: AppEntityIcon
    let repoTitle: String
    let organizationName: String?
    let onToggle: () -> Void
    @ViewBuilder let trailingContent: () -> TrailingContent

    package static var chromePolicy: SidebarHeaderChromePolicy {
        SidebarSourceGroupHeader<TrailingContent>.chromePolicy
    }

    static var leadingInset: CGFloat {
        SidebarSourceGroupHeader<TrailingContent>.leadingInset
    }

    package init(
        isCollapsed: Bool,
        octiconLoader: OcticonLoader,
        icon: AppEntityIcon = .repo,
        repoTitle: String,
        organizationName: String?,
        onToggle: @escaping () -> Void,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent
    ) {
        self.isCollapsed = isCollapsed
        self.octiconLoader = octiconLoader
        self.icon = icon
        self.repoTitle = repoTitle
        self.organizationName = organizationName
        self.onToggle = onToggle
        self.trailingContent = trailingContent
    }

    package var body: some View {
        SidebarSourceGroupHeader(
            isCollapsed: isCollapsed,
            octiconLoader: octiconLoader,
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
    package init(
        isCollapsed: Bool,
        octiconLoader: OcticonLoader,
        icon: AppEntityIcon = .repo,
        repoTitle: String,
        organizationName: String?,
        onToggle: @escaping () -> Void
    ) {
        self.isCollapsed = isCollapsed
        self.octiconLoader = octiconLoader
        self.icon = icon
        self.repoTitle = repoTitle
        self.organizationName = organizationName
        self.onToggle = onToggle
        self.trailingContent = { EmptyView() }
    }
}
