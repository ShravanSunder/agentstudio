import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxSidebarStateAtom")
struct InboxSidebarStateAtomTests {
    @Test("consume returns pending filter once")
    func consumeReturnsPendingFilterOnce() {
        let atom = InboxSidebarStateAtom()
        let filter = InboxFilter.worktree(id: UUID())

        atom.setPendingFilter(filter)

        #expect(atom.peekPendingFilter() == filter)
        #expect(atom.consumePendingFilter() == filter)
        #expect(atom.peekPendingFilter() == nil)
        #expect(atom.consumePendingFilter() == nil)
    }

    @Test("clear removes the pending one-shot filter")
    func clearRemovesPendingFilter() {
        let atom = InboxSidebarStateAtom()
        atom.setPendingFilter(.repo(id: UUID()))

        atom.clearPendingFilter()

        #expect(atom.peekPendingFilter() == nil)
    }

    @Test("inbox groups default expanded and track collapsed keys only")
    func inboxGroupsDefaultExpandedAndTrackCollapsedKeysOnly() {
        let atom = InboxSidebarStateAtom()

        #expect(!atom.isGroupCollapsed(InboxNotificationGroupKey("today")))

        atom.setGroupCollapsed(InboxNotificationGroupKey("today"), isCollapsed: true)
        #expect(atom.collapsedGroups == [InboxNotificationGroupKey("today")])
        #expect(atom.isGroupCollapsed(InboxNotificationGroupKey("today")))

        atom.toggleGroupCollapse(InboxNotificationGroupKey("today"))
        #expect(!atom.isGroupCollapsed(InboxNotificationGroupKey("today")))
        #expect(atom.collapsedGroups.isEmpty)
    }

    @Test("hydrate replaces collapsed group memory")
    func hydrateReplacesCollapsedGroupMemory() {
        let atom = InboxSidebarStateAtom()

        atom.hydrate(collapsedGroups: [InboxNotificationGroupKey("kind:terminal")])

        #expect(atom.collapsedGroups == [InboxNotificationGroupKey("kind:terminal")])

        atom.clearCollapsedGroups()

        #expect(atom.collapsedGroups.isEmpty)
    }
}
