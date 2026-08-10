import SwiftUI
import Testing

@testable import AgentStudioSharedComponents

@Suite("SidebarSectionHeader")
struct SidebarSectionHeaderTests {
    @Test("shared subheading normalizes every surface title for uniform small caps")
    @MainActor
    func sharedSubheadingNormalizesEverySurfaceTitleForUniformSmallCaps() {
        #expect(SectionSubheadingLabel.displayTitle(for: "Recent Repositories") == "recent repositories")
        #expect(SectionSubheadingLabel.displayTitle(for: "Favorites") == "favorites")
    }

    @Test("header row accepts custom content without owning action")
    @MainActor
    func headerRowAcceptsCustomContentWithoutOwningAction() {
        let row = SidebarSectionHeaderRow(isCollapsed: false) {
            Text("agent-studio")
        } trailingContent: {
            Text("3")
        }

        #expect(String(describing: type(of: row)).contains("SidebarSectionHeaderRow"))
    }

    @Test("header exposes shared collapsible sidebar section semantics")
    @MainActor
    func headerExposesSharedCollapsibleSidebarSectionSemantics() {
        let header = SidebarSectionHeader(
            label: "agent-studio",
            isCollapsed: false,
            onToggle: {}
        )

        #expect(String(describing: type(of: header)).contains("SidebarSectionHeader"))
    }

    @Test("section header accepts custom label and trailing content")
    @MainActor
    func sectionHeaderAcceptsCustomLabelAndTrailingContent() {
        let header = SidebarSectionHeader(
            isCollapsed: false,
            onToggle: {},
            label: {
                HStack {
                    Text("agent-studio")
                    Text("ShravanSunder")
                }
            },
            trailingContent: {
                UnreadCountBadge(text: "7")
            }
        )

        #expect(String(describing: type(of: header)).contains("SidebarSectionHeader"))
    }

    @Test("repo group header centralizes repo sidebar chrome")
    @MainActor
    func repoGroupHeaderCentralizesRepoSidebarChrome() {
        let header = SidebarRepoGroupHeader(
            isCollapsed: false,
            octiconLoader: makeSharedComponentsTestOcticonLoader(),
            repoTitle: "agent-studio",
            organizationName: "ShravanSunder",
            onToggle: {},
            trailingContent: {
                UnreadCountBadge(text: "3")
            }
        )

        #expect(String(describing: type(of: header)).contains("SidebarRepoGroupHeader"))
    }
}
