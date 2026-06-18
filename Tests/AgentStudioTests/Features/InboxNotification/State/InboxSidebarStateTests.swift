import Foundation
import Observation
import Testing

@testable import AgentStudio

private final class ObservationInvalidationCounter: @unchecked Sendable {
    var didInvalidate = false
}

@MainActor
@Suite("InboxSidebarState")
struct InboxSidebarStateTests {
    @Test("composed state forwards runtime and memory writes to split owners")
    func composedStateForwardsRuntimeAndMemoryWritesToSplitOwners() {
        let memoryAtom = InboxSidebarMemoryAtom()
        let runtimeAtom = InboxSidebarRuntimeAtom()
        let state = InboxSidebarState(memoryAtom: memoryAtom, runtimeAtom: runtimeAtom)
        let filter = InboxFilter.repo(id: UUID())
        let groupKey = InboxNotificationGroupKey("today")

        state.setPendingFilter(filter)
        state.setGroupCollapsed(groupKey, isCollapsed: true)

        #expect(runtimeAtom.peekPendingFilter() == filter)
        #expect(memoryAtom.collapsedGroups == [groupKey])
        #expect(state.peekPendingFilter() == filter)
        #expect(state.isGroupCollapsed(groupKey))
    }

    @Test("consume returns pending filter once")
    func consumeReturnsPendingFilterOnce() {
        let atom = InboxSidebarState()
        let filter = InboxFilter.worktree(id: UUID())

        atom.setPendingFilter(filter)

        #expect(atom.peekPendingFilter() == filter)
        #expect(atom.consumePendingFilter() == filter)
        #expect(atom.peekPendingFilter() == nil)
        #expect(atom.consumePendingFilter() == nil)
    }

    @Test("consume returns pending display override once")
    func consumeReturnsPendingDisplayOverrideOnce() {
        let atom = InboxSidebarState()
        let override = InboxNotificationDisplayOverride(contentMode: .rollUpAlerts, rowStateFilter: .unreadOnly)

        atom.setPendingDisplayOverride(override)

        #expect(atom.peekPendingDisplayOverride() == override)
        #expect(atom.consumePendingDisplayOverride() == override)
        #expect(atom.peekPendingDisplayOverride() == nil)
        #expect(atom.consumePendingDisplayOverride() == nil)
    }

    @Test("clear removes the pending one-shot filter")
    func clearRemovesPendingFilter() {
        let atom = InboxSidebarState()
        atom.setPendingFilter(.repo(id: UUID()))
        atom.setPendingDisplayOverride(.init(contentMode: .rollUpAlerts, rowStateFilter: .unreadOnly))

        atom.clearPendingFilter()
        atom.clearPendingDisplayOverride()

        #expect(atom.peekPendingFilter() == nil)
        #expect(atom.peekPendingDisplayOverride() == nil)
    }

    @Test("inbox groups default expanded and track collapsed keys only")
    func inboxGroupsDefaultExpandedAndTrackCollapsedKeysOnly() {
        let atom = InboxSidebarState()

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
        let atom = InboxSidebarState()

        atom.hydrate(collapsedGroups: [InboxNotificationGroupKey("kind:terminal")])

        #expect(atom.collapsedGroups == [InboxNotificationGroupKey("kind:terminal")])

        atom.clearCollapsedGroups()

        #expect(atom.collapsedGroups.isEmpty)
    }

    @Test("hydrate clears runtime pending filter")
    func hydrateClearsRuntimePendingFilter() {
        let atom = InboxSidebarState()
        atom.setPendingFilter(.repo(id: UUID()))
        atom.setPendingDisplayOverride(.init(contentMode: .rollUpAlerts, rowStateFilter: .unreadOnly))

        atom.hydrate(collapsedGroups: [InboxNotificationGroupKey("repo:agent-studio")])

        #expect(atom.peekPendingFilter() == nil)
        #expect(atom.peekPendingDisplayOverride() == nil)
        #expect(atom.collapsedGroups == [InboxNotificationGroupKey("repo:agent-studio")])
    }

    @Test("collapsed group observation ignores runtime pending filter")
    func collapsedGroupObservationIgnoresRuntimePendingFilter() {
        let memoryAtom = InboxSidebarMemoryAtom()
        let runtimeAtom = InboxSidebarRuntimeAtom()
        let state = InboxSidebarState(memoryAtom: memoryAtom, runtimeAtom: runtimeAtom)
        let invalidationCounter = ObservationInvalidationCounter()

        withObservationTracking {
            _ = state.collapsedGroups
        } onChange: {
            invalidationCounter.didInvalidate = true
        }

        runtimeAtom.setPendingFilter(.repo(id: UUID()))
        #expect(!invalidationCounter.didInvalidate)

        memoryAtom.setGroupCollapsed(InboxNotificationGroupKey("repo:agent-studio"), isCollapsed: true)
        #expect(invalidationCounter.didInvalidate)
    }
}
