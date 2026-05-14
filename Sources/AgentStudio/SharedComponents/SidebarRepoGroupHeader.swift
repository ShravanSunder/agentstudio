import SwiftUI

struct SidebarRepoGroupHeader<TrailingContent: View>: View {
    let isCollapsed: Bool
    let repoTitle: String
    let organizationName: String?
    let onToggle: () -> Void
    @ViewBuilder let trailingContent: () -> TrailingContent

    static var chromePolicy: SidebarHeaderChromePolicy {
        .repoGroupHeader
    }

    static var leadingInset: CGFloat {
        AppStyles.Shell.Sidebar.listRowLeadingInset
    }

    var body: some View {
        Button(action: onToggle) {
            SidebarSectionHeaderRow(isCollapsed: isCollapsed) {
                SidebarGroupRow(
                    repoTitle: repoTitle,
                    organizationName: organizationName
                )
            } trailingContent: {
                trailingContent()
            }
            .padding(.leading, Self.leadingInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension SidebarRepoGroupHeader where TrailingContent == EmptyView {
    init(
        isCollapsed: Bool,
        repoTitle: String,
        organizationName: String?,
        onToggle: @escaping () -> Void
    ) {
        self.isCollapsed = isCollapsed
        self.repoTitle = repoTitle
        self.organizationName = organizationName
        self.onToggle = onToggle
        self.trailingContent = { EmptyView() }
    }
}
