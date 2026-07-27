import SwiftUI

struct RepoExplorerResolvedGroupHeaderRow: View {
    let octiconLoader: OcticonLoader
    let isExpanded: Bool
    let repoTitle: String
    let organizationName: String?

    var body: some View {
        SidebarSectionHeaderRow(isCollapsed: !isExpanded) {
            SidebarGroupRow(
                octiconLoader: octiconLoader,
                repoTitle: repoTitle,
                organizationName: organizationName
            )
        }
    }
}
