import SwiftUI

struct SidebarRepoGroupHeader<TrailingContent: View>: View {
    let isCollapsed: Bool
    let repoTitle: String
    let organizationName: String?
    let onToggle: () -> Void
    @ViewBuilder let trailingContent: () -> TrailingContent

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
            .padding(.leading, AppStyles.Shell.Sidebar.listRowLeadingInset)
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
