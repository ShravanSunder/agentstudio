import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

package struct RepoExplorerResolvedGroupHeaderRow: View {
    let octiconLoader: OcticonLoader
    let isExpanded: Bool
    let repoTitle: String
    let organizationName: String?

    package init(
        octiconLoader: OcticonLoader,
        isExpanded: Bool,
        repoTitle: String,
        organizationName: String?
    ) {
        self.octiconLoader = octiconLoader
        self.isExpanded = isExpanded
        self.repoTitle = repoTitle
        self.organizationName = organizationName
    }

    package var body: some View {
        SidebarSectionHeaderRow(isCollapsed: !isExpanded) {
            SidebarGroupRow(
                octiconLoader: octiconLoader,
                repoTitle: repoTitle,
                organizationName: organizationName
            )
        }
    }
}
