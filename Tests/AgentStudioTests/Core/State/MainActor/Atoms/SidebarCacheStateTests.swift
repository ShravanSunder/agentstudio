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

    @Test("checkout color atom owns only checkout colors")
    func checkoutColorAtomOwnsOnlyCheckoutColors() {
        let atom = SidebarCheckoutColorAtom()

        #expect(atom.checkoutColors.isEmpty)

        atom.setCheckoutColor("#22cc88", for: SidebarCheckoutColorKey("repoKey"))
        #expect(atom.checkoutColors[SidebarCheckoutColorKey("repoKey")] == "#22cc88")

        atom.setCheckoutColor(nil, for: SidebarCheckoutColorKey("repoKey"))
        #expect(atom.checkoutColors[SidebarCheckoutColorKey("repoKey")] == nil)
    }

    @Test("sidebar cache state composes expanded groups and checkout colors")
    func sidebarCacheStateComposesSplitOwners() {
        let expandedGroups = SidebarExpandedGroupAtom()
        let checkoutColors = SidebarCheckoutColorAtom()
        let state = SidebarCacheState(
            expandedGroupAtom: expandedGroups,
            checkoutColorAtom: checkoutColors
        )

        state.hydrate(
            expandedGroups: [SidebarGroupKey("repo:a")],
            checkoutColors: [SidebarCheckoutColorKey("repo:a"): "#111111"]
        )

        #expect(expandedGroups.expandedGroups == [SidebarGroupKey("repo:a")])
        #expect(checkoutColors.checkoutColors == [SidebarCheckoutColorKey("repo:a"): "#111111"])
        #expect(state.expandedGroups == [SidebarGroupKey("repo:a")])
        #expect(state.checkoutColors == [SidebarCheckoutColorKey("repo:a"): "#111111"])

        state.clear()

        #expect(expandedGroups.expandedGroups.isEmpty)
        #expect(checkoutColors.checkoutColors.isEmpty)
    }
}
