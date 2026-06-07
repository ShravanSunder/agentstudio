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
        let sidebarMemory1 = InboxSidebarMemoryAtom()
        let sidebarState1 = InboxSidebarState(memoryAtom: sidebarMemory1)
        let clock = TestPushClock()
        let store1 = InboxNotificationStore(
            inboxAtom: atom1,
            prefsAtom: prefs1,
            sidebarState: sidebarState1,
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
            isDismissedFromPaneInbox: false
        )

        atom1.append(note)
        prefs1.setGrouping(.byRepo)
        prefs1.setSort(.oldestFirst)
        prefs1.setBellEnabled(true)
        sidebarMemory1.setGroupCollapsed(InboxNotificationGroupKey("repo:agent-studio"), isCollapsed: true)
        try await store1.save()

        let atom2 = InboxNotificationAtom()
        let prefs2 = InboxNotificationPrefsAtom()
        let sidebarState2 = InboxSidebarState()
        let store2 = InboxNotificationStore(
            inboxAtom: atom2,
            prefsAtom: prefs2,
            sidebarState: sidebarState2,
            fileURL: url,
            clock: clock
        )
        try store2.load()

        #expect(atom2.notifications.count == 1)
        #expect(atom2.notifications[0].id == note.id)
        #expect(prefs2.grouping == .byTab)
        #expect(prefs2.sort == .newestFirst)
        #expect(prefs2.bellEnabled == false)
        #expect(sidebarState2.collapsedGroups == [InboxNotificationGroupKey("repo:agent-studio")])
    }

    @Test("load resets runtime-only pending sidebar filter")
    func loadResetsRuntimeOnlyPendingSidebarFilter() async throws {
        let url = makeTempURL()
        let inboxAtom = InboxNotificationAtom()
        let prefsAtom = InboxNotificationPrefsAtom()
        let sidebarState = InboxSidebarState()
        let store = InboxNotificationStore(
            inboxAtom: inboxAtom,
            prefsAtom: prefsAtom,
            sidebarState: sidebarState,
            fileURL: url
        )

        sidebarState.setGroupCollapsed(InboxNotificationGroupKey("repo:agent-studio"), isCollapsed: true)
        try await store.save()
        sidebarState.setPendingFilter(.repo(id: UUID()))

        try store.load()

        #expect(sidebarState.peekPendingFilter() == nil)
        #expect(sidebarState.collapsedGroups == [InboxNotificationGroupKey("repo:agent-studio")])
    }

    @Test("save writes schema version three for feature sidebar state")
    func saveWritesSchemaVersionThreeForFeatureSidebarState() async throws {
        let url = makeTempURL()
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        let sidebarState = InboxSidebarState()
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            sidebarState: sidebarState,
            fileURL: url
        )

        sidebarState.setGroupCollapsed(InboxNotificationGroupKey("repo:agent-studio"), isCollapsed: true)
        sidebarState.setPendingFilter(.repo(id: UUID()))
        try await store.save()

        let data = try Data(contentsOf: url)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["schemaVersion"] as? Int == 3)
        let sidebarStatePayload = try #require(payload["sidebarState"] as? [String: Any])
        #expect(sidebarStatePayload["collapsedGroups"] != nil)
        #expect(sidebarStatePayload["pendingFilter"] == nil)
    }

    @Test("load accepts schema one pane source without denormalized display fields")
    func loadAcceptsSchemaOnePaneSourceWithoutDenormalizedDisplayFields() throws {
        let url = makeTempURL()
        let paneId = UUID()
        let notificationId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "notifications": [
                    {
                        "id": "\(notificationId.uuidString)",
                        "timestamp": "2026-05-01T12:00:00Z",
                        "kind": "agentRpc",
                        "title": "Legacy",
                        "body": null,
                        "source": {
                            "pane": {
                                "_0": {
                                    "paneId": "\(paneId.uuidString)"
                                }
                            }
                        },
                        "isRead": false,
                        "isDismissedFromPaneInbox": false
                    }
                ],
                "prefs": {
                    "grouping": "none",
                    "sort": "newestFirst",
                    "bellEnabled": false
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

        let notification = try #require(atom.notifications.first)
        #expect(notification.id == notificationId)
        guard case .pane(let paneSource) = notification.source else {
            Issue.record("Expected legacy notification to decode as pane source")
            return
        }
        #expect(paneSource.paneId == paneId)
        #expect(paneSource.paneRole == .main)
        #expect(paneSource.tabDisplayLabel == nil)
        #expect(paneSource.runtimeDisplayLabel == nil)
        let display = InboxNotificationSourceDisplay(notification: notification)
        #expect(display.sourceLine == "Pane event")
        #expect(display.groupLabel(for: .byRepo) == "Pane")
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
        #expect(prefs.grouping == .byTab)
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

        try store.load()

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(atom.notifications.isEmpty)
        #expect(prefs.grouping == .byTab)
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

        try store.load()

        #expect(prefs.grouping == .byTab)
        #expect(prefs.bellEnabled == false)
        #expect(reportedRecovery?.store == .notificationInbox)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)
    }

    @Test("load accepts schema two payloads from sibling inbox builds")
    func loadAcceptsSchemaTwoPayloadsFromSiblingInboxBuilds() throws {
        let url = makeTempURL()
        let notificationId = UUID()
        let json = """
            {
                "schemaVersion": 2,
                "notifications": [
                    {
                        "id": "\(notificationId.uuidString)",
                        "timestamp": "2026-05-12T10:21:49Z",
                        "kind": "persistenceRecovery",
                        "title": "Notification inbox reset",
                        "body": "The saved file could not be loaded, so it was moved aside and defaults were used.",
                        "source": { "global": {} },
                        "isRead": true,
                        "isDismissedFromPaneInbox": true
                    }
                ],
                "prefs": {
                    "grouping": "none",
                    "sort": "newestFirst",
                    "bellEnabled": false
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

        try store.load()

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(atom.notifications.map(\.id) == [notificationId])
        #expect(atom.notifications.first?.kind == .persistenceRecovery)
        #expect(reportedRecovery == nil)
    }

    @Test("load quarantines bad notification slice")
    func loadQuarantinesBadNotificationSlice() throws {
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
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url,
            recoveryReporter: { reportedRecovery = $0 }
        )

        try store.load()

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(atom.notifications.isEmpty)
        #expect(prefs.grouping == .byTab)
        #expect(prefs.sort == .newestFirst)
        #expect(!prefs.bellEnabled)
        #expect(reportedRecovery?.store == .notificationInbox)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)
    }

    @Test("save cancels pending debounced save before writing final snapshot")
    func saveCancelsPendingDebouncedSaveBeforeWritingFinalSnapshot() async throws {
        let url = makeTempURL()
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        let clock = TestPushClock()
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url,
            clock: clock,
            debounceDuration: .milliseconds(10)
        )
        let staleNotification = InboxNotification(
            id: UUID(),
            timestamp: Date(),
            kind: .agentDesktopNotification,
            title: "Stale",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        let finalNotification = InboxNotification(
            id: UUID(),
            timestamp: Date(),
            kind: .agentDesktopNotification,
            title: "Final",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )

        atom.append(staleNotification)
        store.scheduleDebouncedSave()
        await clock.waitForPendingSleepCount()
        atom.append(finalNotification)
        try await store.save()
        #expect(clock.pendingSleepCount == 0)
        clock.advance(by: .milliseconds(10))
        await Task.yield()

        let restoredAtom = InboxNotificationAtom()
        let restoredStore = InboxNotificationStore(
            inboxAtom: restoredAtom,
            prefsAtom: InboxNotificationPrefsAtom(),
            fileURL: url
        )
        try restoredStore.load()

        #expect(restoredAtom.notifications.map(\.id) == [staleNotification.id, finalNotification.id])
    }

    @Test("load leaves legacy preference fields to settings store")
    func loadLeavesLegacyPreferenceFieldsToSettingsStore() throws {
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
        prefs.setGrouping(.byRepo)
        prefs.setSort(.newestFirst)
        prefs.setBellEnabled(false)
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url
        )

        try store.load()

        #expect(atom.notifications.isEmpty)
        #expect(prefs.grouping == .byRepo)
        #expect(prefs.sort == .newestFirst)
        #expect(!prefs.bellEnabled)
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
                isDismissedFromPaneInbox: false
            )
        )
        store.scheduleDebouncedSave()

        await assertEventuallyMain("debounce failure should fall through to save") {
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    @Test("save failure reports persistence recovery event")
    func saveFailureReportsPersistenceRecoveryEvent() async {
        let parentFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-save-parent-\(UUID().uuidString)")
        try? Data("not-a-directory".utf8).write(to: parentFileURL, options: .atomic)
        let fileURL = parentFileURL.appending(path: "notification-inbox.json")
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: fileURL,
            recoveryReporter: { reportedRecovery = $0 }
        )

        await #expect(throws: Error.self) {
            try await store.save()
        }

        #expect(reportedRecovery?.store == .notificationInbox)
        #expect(reportedRecovery?.recovery == .saveFailed)
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
