import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationPrefsAtom")
struct InboxNotificationPrefsAtomTests {
    @Test("defaults")
    func defaults() {
        let atom = InboxNotificationPrefsAtom()
        #expect(atom.grouping == .none)
        #expect(atom.sort == .newestFirst)
        #expect(atom.bellEnabled == false)
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
}
