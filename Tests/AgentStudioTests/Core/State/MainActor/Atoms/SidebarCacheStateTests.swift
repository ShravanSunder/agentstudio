import Testing

@testable import AgentStudio

@MainActor
@Suite("Sidebar cache split atoms")
struct SidebarCacheStateTests {
    @Test("expanded group atom owns only expanded groups")
    func expandedGroupAtomOwnsOnlyExpandedGroups() {
        let atom = SidebarExpandedGroupAtom()

        #expect(atom.expandedGroups.isEmpty)

        atom.setGroupExpanded("repo:agent-studio", isExpanded: true)
        atom.setGroupExpanded("repo:personal", isExpanded: true)
        atom.setGroupExpanded("repo:personal", isExpanded: false)

        #expect(atom.expandedGroups == [SidebarGroupKey("repo:agent-studio")])
    }

    @Test("sidebar cache state composes expanded group owner")
    func sidebarCacheStateComposesExpandedGroupOwner() {
        let expandedGroups = SidebarExpandedGroupAtom()
        let state = SidebarCacheState(
            expandedGroupAtom: expandedGroups
        )

        state.hydrate(
            expandedGroups: [SidebarGroupKey("repo:a")]
        )

        #expect(expandedGroups.expandedGroups == [SidebarGroupKey("repo:a")])
        #expect(state.expandedGroups == [SidebarGroupKey("repo:a")])

        state.clear()

        #expect(expandedGroups.expandedGroups.isEmpty)
    }
}
