import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationStore")
struct InboxNotificationStoreTests {
    private func makeTempURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("notification-inbox.json")
    }

    @Test("roundtrip: save + load returns equal notifications")
    func roundtrip() async throws {
        let url = makeTempURL()
        let atom1 = InboxNotificationAtom()
        let prefs1 = InboxNotificationPrefsAtom()
        let clock = TestPushClock()
        let store1 = InboxNotificationStore(
            inboxAtom: atom1,
            prefsAtom: prefs1,
            fileURL: url,
            clock: clock
        )

        let note = InboxNotification(
            id: UUID(),
            timestamp: Date(),
            kind: .agentDesktopNotification,
            title: "Test",
            body: nil,
            source: .pane(.init(paneId: UUID())),
            isRead: false,
            isDismissedFromDrawer: false
        )

        atom1.append(note)
        prefs1.setGrouping(.byRepo)
        prefs1.setSort(.oldestFirst)
        prefs1.setBellEnabled(true)
        try await store1.save()

        let atom2 = InboxNotificationAtom()
        let prefs2 = InboxNotificationPrefsAtom()
        let store2 = InboxNotificationStore(
            inboxAtom: atom2,
            prefsAtom: prefs2,
            fileURL: url,
            clock: clock
        )
        try store2.load()

        #expect(atom2.notifications.count == 1)
        #expect(atom2.notifications[0].id == note.id)
        #expect(prefs2.grouping == .byRepo)
        #expect(prefs2.sort == .oldestFirst)
        #expect(prefs2.bellEnabled == true)
    }

    @Test("load from missing file uses defaults")
    func loadMissingFileUsesDefaults() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID()).json")
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url
        )

        try store.load()

        #expect(atom.notifications.isEmpty)
        #expect(prefs.grouping == .none)
        #expect(prefs.bellEnabled == false)
    }

    @Test("load from corrupt file quarantines the file before falling back to defaults")
    func loadCorruptFileQuarantinesBeforeDefaulting() throws {
        let url = makeTempURL()
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url,
            recoveryReporter: { reportedRecovery = $0 }
        )

        try? store.load()

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(atom.notifications.isEmpty)
        #expect(prefs.grouping == .none)
        #expect(prefs.bellEnabled == false)

        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        .filter {
            $0.lastPathComponent.hasPrefix("notification-inbox.corrupt-")
        }
        #expect(quarantinedFiles.count == 1)
        #expect(reportedRecovery?.store == .notificationInbox)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)
        #expect(reportedRecovery?.quarantinedFilename == quarantinedFiles.first?.lastPathComponent)
    }

    @Test("load from unknown schema quarantines instead of interpreting as v1")
    func loadUnknownSchemaQuarantinesInsteadOfInterpretingAsV1() throws {
        let url = makeTempURL()
        let json = """
            {
                "schemaVersion": 99999,
                "notifications": [],
                "prefs": {
                    "grouping": "byRepo",
                    "sort": "newestFirst",
                    "bellEnabled": true
                }
            }
            """
        try Data(json.utf8).write(to: url, options: .atomic)
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url,
            recoveryReporter: { reportedRecovery = $0 }
        )

        #expect(throws: Error.self) {
            try store.load()
        }

        #expect(prefs.grouping == .none)
        #expect(prefs.bellEnabled == false)
        #expect(reportedRecovery?.store == .notificationInbox)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)
    }

    @Test("load defaults bad notification slice while preserving valid prefs")
    func loadDefaultsBadNotificationSliceWhilePreservingPrefs() throws {
        let url = makeTempURL()
        let json = """
            {
                "schemaVersion": 1,
                "notifications": 42,
                "prefs": {
                    "grouping": "byRepo",
                    "sort": "oldestFirst",
                    "bellEnabled": true
                }
            }
            """
        try Data(json.utf8).write(to: url, options: .atomic)
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url
        )

        try store.load()

        #expect(atom.notifications.isEmpty)
        #expect(prefs.grouping == .byRepo)
        #expect(prefs.sort == .oldestFirst)
        #expect(prefs.bellEnabled)
    }

    @Test("load defaults bad preference fields independently")
    func loadDefaultsBadPreferenceFieldsIndependently() throws {
        let url = makeTempURL()
        let json = """
            {
                "schemaVersion": 1,
                "notifications": [],
                "prefs": {
                    "grouping": "not-a-group",
                    "sort": "oldestFirst",
                    "bellEnabled": true
                }
            }
            """
        try Data(json.utf8).write(to: url, options: .atomic)
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url
        )

        try store.load()

        #expect(atom.notifications.isEmpty)
        #expect(prefs.grouping == .none)
        #expect(prefs.sort == .oldestFirst)
        #expect(prefs.bellEnabled)
    }

    @Test("debounce clock failure still saves immediately")
    func debounceClockFailureStillSavesImmediately() async throws {
        let url = makeTempURL()
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url,
            clock: FailingClock()
        )

        atom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(),
                kind: .agentDesktopNotification,
                title: "Saved",
                body: nil,
                source: .global,
                isRead: false,
                isDismissedFromDrawer: false
            )
        )
        store.scheduleDebouncedSave()

        await assertEventuallyMain("debounce failure should fall through to save") {
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    private struct FailingClock: Clock {
        struct Failure: Error {}

        private let base = ContinuousClock()

        var now: ContinuousClock.Instant {
            base.now
        }

        var minimumResolution: Duration {
            base.minimumResolution
        }

        func sleep(
            until deadline: ContinuousClock.Instant,
            tolerance: Duration? = nil
        ) async throws {
            throw Failure()
        }
    }
}
