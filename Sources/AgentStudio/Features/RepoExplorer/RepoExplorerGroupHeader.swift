import SwiftUI

struct RepoExplorerResolvedGroupHeaderRow: View {
    let isExpanded: Bool
    let repoTitle: String
    let organizationName: String?

    var body: some View {
        SidebarSectionHeaderRow(isCollapsed: !isExpanded) {
            SidebarGroupRow(
                repoTitle: repoTitle,
                organizationName: organizationName
            )
        }
    }
}
