import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationPrefsAtom")
struct InboxNotificationPrefsAtomTests {
    @Test("defaults")
    func defaults() {
        let atom = InboxNotificationPrefsAtom()
        #expect(atom.grouping == .byTab)
        #expect(atom.sort == .newestFirst)
        #expect(atom.bellEnabled == false)
        #expect(atom.globalInboxContentMode == .rollUpAlerts)
        #expect(atom.globalInboxRowStateFilter == .unreadOnly)
        #expect(atom.paneInboxContentMode == .rollUpAlerts)
        #expect(atom.paneInboxRowStateFilter == .unreadOnly)
    }

    @Test("setGrouping")
    func setGrouping() {
        let atom = InboxNotificationPrefsAtom()
        atom.setGrouping(.byRepo)
        #expect(atom.grouping == .byRepo)
    }

    @Test("setSort")
    func setSort() {
        let atom = InboxNotificationPrefsAtom()
        atom.setSort(.oldestFirst)
        #expect(atom.sort == .oldestFirst)
    }

    @Test("setBellEnabled")
    func setBellEnabled() {
        let atom = InboxNotificationPrefsAtom()
        atom.setBellEnabled(true)
        #expect(atom.bellEnabled == true)
        atom.setBellEnabled(false)
        #expect(atom.bellEnabled == false)
    }

    @Test("setGlobalInboxContentMode")
    func setGlobalInboxContentMode() {
        let atom = InboxNotificationPrefsAtom()
        atom.setGlobalInboxContentMode(.activity)
        #expect(atom.globalInboxContentMode == .activity)
        #expect(atom.paneInboxContentMode == .rollUpAlerts)
    }

    @Test("setPaneInboxRowStateFilter")
    func setPaneInboxRowStateFilter() {
        let atom = InboxNotificationPrefsAtom()
        atom.setPaneInboxRowStateFilter(.all)
        #expect(atom.paneInboxRowStateFilter == .all)
        #expect(atom.globalInboxRowStateFilter == .unreadOnly)
    }
}
