import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Sidebar cache split atoms")
struct SidebarCacheStateTests {
    @Test("collapsed group atom makes unseen groups expanded and remembers explicit collapse")
    func collapsedGroupAtomOwnsOnlyCollapsedGroups() {
        let atom = SidebarCollapsedGroupAtom()
        let unseenGroup = SidebarGroupKey("repo:unseen")

        #expect(atom.collapsedGroups.isEmpty)
        #expect(!atom.collapsedGroups.contains(unseenGroup))

        atom.setGroupExpanded("repo:agent-studio", isExpanded: false)
        atom.setGroupExpanded("repo:personal", isExpanded: false)
        atom.setGroupExpanded("repo:personal", isExpanded: true)

        #expect(atom.collapsedGroups == [SidebarGroupKey("repo:agent-studio")])
    }

    @Test("sidebar cache state composes collapsed group owner")
    func sidebarCacheStateComposesCollapsedGroupOwner() {
        let collapsedGroups = SidebarCollapsedGroupAtom()
        let state = SidebarCacheState(
            collapsedGroupAtom: collapsedGroups
        )

        state.hydrate(
            collapsedGroups: [SidebarGroupKey("repo:a")]
        )

        #expect(collapsedGroups.collapsedGroups == [SidebarGroupKey("repo:a")])
        #expect(state.collapsedGroups == [SidebarGroupKey("repo:a")])

        state.clear()

        #expect(collapsedGroups.collapsedGroups.isEmpty)
    }
}
