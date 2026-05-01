import Testing

@testable import AgentStudio

@MainActor
@Suite("SidebarCacheAtom")
struct SidebarCacheAtomTests {
    @Test("defaults are empty durable sidebar memory")
    func defaultsAreEmptyDurableSidebarMemory() {
        let atom = SidebarCacheAtom()

        #expect(atom.expandedGroups.isEmpty)
        #expect(atom.checkoutColors.isEmpty)
        #expect(atom.collapsedInboxGroups.isEmpty)
    }

    @Test("group expansion adds and removes keys")
    func groupExpansionAddsAndRemovesKeys() {
        let atom = SidebarCacheAtom()

        atom.setGroupExpanded("repo:agent-studio", isExpanded: true)
        atom.setGroupExpanded("repo:personal", isExpanded: true)
        atom.setGroupExpanded("repo:personal", isExpanded: false)

        #expect(atom.expandedGroups == [SidebarGroupKey("repo:agent-studio")])
    }

    @Test("checkout colors set and clear by stable key")
    func checkoutColorsSetAndClearByStableKey() {
        let atom = SidebarCacheAtom()

        atom.setCheckoutColor("#22cc88", for: SidebarCheckoutColorKey("repoKey"))
        #expect(atom.checkoutColors[SidebarCheckoutColorKey("repoKey")] == "#22cc88")

        atom.setCheckoutColor(nil, for: SidebarCheckoutColorKey("repoKey"))
        #expect(atom.checkoutColors[SidebarCheckoutColorKey("repoKey")] == nil)
    }

    @Test("inbox groups default expanded and track collapsed keys only")
    func inboxGroupsDefaultExpandedAndTrackCollapsedKeysOnly() {
        let atom = SidebarCacheAtom()

        #expect(!atom.isInboxGroupCollapsed(InboxNotificationGroupKey("today")))

        atom.setInboxGroupCollapsed(InboxNotificationGroupKey("today"), isCollapsed: true)
        #expect(atom.collapsedInboxGroups == [InboxNotificationGroupKey("today")])
        #expect(atom.isInboxGroupCollapsed(InboxNotificationGroupKey("today")))

        atom.toggleInboxGroupCollapse(InboxNotificationGroupKey("today"))
        #expect(!atom.isInboxGroupCollapsed(InboxNotificationGroupKey("today")))
        #expect(atom.collapsedInboxGroups.isEmpty)
    }

    @Test("hydrate replaces every cache slice")
    func hydrateReplacesEveryCacheSlice() {
        let atom = SidebarCacheAtom()

        atom.hydrate(
            expandedGroups: [SidebarGroupKey("repo:a")],
            checkoutColors: [SidebarCheckoutColorKey("repo:a"): "#111111"],
            collapsedInboxGroups: [InboxNotificationGroupKey("kind:terminal")]
        )

        #expect(atom.expandedGroups == [SidebarGroupKey("repo:a")])
        #expect(atom.checkoutColors == [SidebarCheckoutColorKey("repo:a"): "#111111"])
        #expect(atom.collapsedInboxGroups == [InboxNotificationGroupKey("kind:terminal")])
    }

    @Test("clear returns to empty memory")
    func clearReturnsToEmptyMemory() {
        let atom = SidebarCacheAtom()
        atom.hydrate(
            expandedGroups: [SidebarGroupKey("repo:a")],
            checkoutColors: [SidebarCheckoutColorKey("repo:a"): "#111111"],
            collapsedInboxGroups: [InboxNotificationGroupKey("kind:terminal")]
        )

        atom.clear()

        #expect(atom.expandedGroups.isEmpty)
        #expect(atom.checkoutColors.isEmpty)
        #expect(atom.collapsedInboxGroups.isEmpty)
    }
}
