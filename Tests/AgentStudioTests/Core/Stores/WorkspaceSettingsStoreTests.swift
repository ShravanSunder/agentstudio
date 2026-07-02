import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSettingsStoreTests {
    private let tempDir: URL

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "workspace-settings-store-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    @Test
    func flushAndRestoreRoundTripsSettings() throws {
        let workspaceId = UUID()
        let editorPreference = EditorPreferenceAtom()
        let inboxPrefs = InboxNotificationPrefsAtom()
        let store = makeStore(
            editorPreference: editorPreference,
            inboxPrefs: inboxPrefs
        )
        editorPreference.setBookmarkedEditor("cursor")
        inboxPrefs.setGrouping(.byRepo)
        inboxPrefs.setSort(.oldestFirst)
        inboxPrefs.setBellEnabled(true)
        inboxPrefs.setGlobalInboxContentMode(.activity)
        inboxPrefs.setGlobalInboxRowStateFilter(.all)
        inboxPrefs.setPaneInboxContentMode(.all)
        inboxPrefs.setPaneInboxRowStateFilter(.unreadOnly)

        try store.flush(for: workspaceId)

        let restoredEditorPreference = EditorPreferenceAtom()
        let restoredInboxPrefs = InboxNotificationPrefsAtom()
        makeStore(
            editorPreference: restoredEditorPreference,
            inboxPrefs: restoredInboxPrefs
        ).restore(for: workspaceId)

        #expect(restoredEditorPreference.bookmarkedEditorId == "cursor")
        #expect(restoredInboxPrefs.grouping == .byRepo)
        #expect(restoredInboxPrefs.sort == .oldestFirst)
        #expect(restoredInboxPrefs.bellEnabled)
        #expect(restoredInboxPrefs.globalInboxContentMode == .activity)
        #expect(restoredInboxPrefs.globalInboxRowStateFilter == .all)
        #expect(restoredInboxPrefs.paneInboxContentMode == .all)
        #expect(restoredInboxPrefs.paneInboxRowStateFilter == .unreadOnly)
    }

    @Test
    func restoreMissingSettingsFileAppliesDefaults() {
        let workspaceId = UUID()
        let editorPreference = EditorPreferenceAtom()
        let inboxPrefs = InboxNotificationPrefsAtom()
        let store = makeStore(
            editorPreference: editorPreference,
            inboxPrefs: inboxPrefs
        )
        editorPreference.setBookmarkedEditor("cursor")
        inboxPrefs.setGrouping(.byRepo)
        inboxPrefs.setSort(.oldestFirst)
        inboxPrefs.setBellEnabled(true)

        store.restore(for: workspaceId)

        #expect(editorPreference.bookmarkedEditorId == nil)
        #expect(inboxPrefs.grouping == .byTab)
        #expect(inboxPrefs.sort == .newestFirst)
        #expect(!inboxPrefs.bellEnabled)
        #expect(inboxPrefs.globalInboxContentMode == .rollUpAlerts)
        #expect(inboxPrefs.globalInboxRowStateFilter == .unreadOnly)
        #expect(inboxPrefs.paneInboxContentMode == .rollUpAlerts)
        #expect(inboxPrefs.paneInboxRowStateFilter == .unreadOnly)
    }

    @Test
    func restoreMissingSettingsFileImportsLegacySettingsSlices() throws {
        let workspaceId = UUID()
        let editorPreference = EditorPreferenceAtom()
        let inboxPrefs = InboxNotificationPrefsAtom()
        let legacyPersistor = WorkspacePersistor(workspacesDir: tempDir)
        try legacyPersistor.saveUI(
            .init(
                workspaceId: workspaceId,
                editorChooserState: .init(bookmarkedEditorId: "cursor")
            )
        )
        let legacyInboxURL = legacyPersistor.notificationInboxFileURL(for: workspaceId)
        let legacyInboxJSON = """
            {
                "schemaVersion": 3,
                "notifications": [],
                "prefs": {
                    "grouping": "byRepo",
                    "sort": "oldestFirst",
                    "bellEnabled": true
                },
                "sidebarState": {
                    "collapsedGroups": []
                }
            }
            """
        try Data(legacyInboxJSON.utf8).write(to: legacyInboxURL, options: .atomic)
        let store = makeStore(
            editorPreference: editorPreference,
            inboxPrefs: inboxPrefs
        )

        store.restore(for: workspaceId)

        #expect(editorPreference.bookmarkedEditorId == "cursor")
        #expect(inboxPrefs.grouping == .byRepo)
        #expect(inboxPrefs.sort == .oldestFirst)
        #expect(inboxPrefs.bellEnabled)
    }

    @Test
    func failedLegacyMaterializationBlocksSettingsArchiveReadiness() throws {
        let workspaceId = UUID()
        let editorPreference = EditorPreferenceAtom()
        let inboxPrefs = InboxNotificationPrefsAtom()
        let legacyPersistor = WorkspacePersistor(workspacesDir: tempDir)
        _ = try seedLegacySettingsSidecars(workspaceId: workspaceId, legacyPersistor: legacyPersistor)
        let blockedDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: "workspace-settings-blocked-\(UUID().uuidString)")
        try Data("not-a-directory".utf8).write(to: blockedDirectoryURL, options: .atomic)
        let store = makeStore(
            editorPreference: editorPreference,
            inboxPrefs: inboxPrefs,
            workspacesDir: blockedDirectoryURL,
            legacyPersistor: legacyPersistor
        )

        store.restore(for: workspaceId)

        #expect(editorPreference.bookmarkedEditorId == "cursor")
        #expect(inboxPrefs.grouping == .byRepo)
        #expect(!store.canArchiveLegacySettingsFiles)
    }

    @Test
    func restoreMissingSettingsFileMaterializesLegacySettingsBeforeSidecarSaves() async throws {
        let workspaceId = UUID()
        let legacyPersistor = WorkspacePersistor(workspacesDir: tempDir)
        let legacyInboxURL = try seedLegacySettingsSidecars(
            workspaceId: workspaceId,
            legacyPersistor: legacyPersistor
        )

        makeStore().restore(for: workspaceId)
        try await scrubLegacySettingsSidecars(
            workspaceId: workspaceId,
            legacyPersistor: legacyPersistor,
            legacyInboxURL: legacyInboxURL
        )

        let restoredEditorPreference = EditorPreferenceAtom()
        let restoredInboxPrefs = InboxNotificationPrefsAtom()
        makeStore(
            editorPreference: restoredEditorPreference,
            inboxPrefs: restoredInboxPrefs
        ).restore(for: workspaceId)

        #expect(restoredEditorPreference.bookmarkedEditorId == "cursor")
        #expect(restoredInboxPrefs.grouping == .byRepo)
        #expect(restoredInboxPrefs.sort == .oldestFirst)
        #expect(restoredInboxPrefs.bellEnabled)
    }

    @Test
    func restoreCorruptSettingsFileAfterSidecarScrubUsesSettingsBackup() async throws {
        let workspaceId = UUID()
        let legacyPersistor = WorkspacePersistor(workspacesDir: tempDir)
        let legacyInboxURL = try seedLegacySettingsSidecars(
            workspaceId: workspaceId,
            legacyPersistor: legacyPersistor
        )
        makeStore().restore(for: workspaceId)
        try await scrubLegacySettingsSidecars(
            workspaceId: workspaceId,
            legacyPersistor: legacyPersistor,
            legacyInboxURL: legacyInboxURL
        )
        try Data("not-json".utf8).write(to: settingsFileURL(for: workspaceId), options: .atomic)

        let restoredEditorPreference = EditorPreferenceAtom()
        let restoredInboxPrefs = InboxNotificationPrefsAtom()
        makeStore(
            editorPreference: restoredEditorPreference,
            inboxPrefs: restoredInboxPrefs
        ).restore(for: workspaceId)

        #expect(restoredEditorPreference.bookmarkedEditorId == "cursor")
        #expect(restoredInboxPrefs.grouping == .byRepo)
        #expect(restoredInboxPrefs.sort == .oldestFirst)
        #expect(restoredInboxPrefs.bellEnabled)
    }

    @Test
    func restoreMissingSettingsFileAfterSidecarScrubUsesSettingsBackup() async throws {
        let workspaceId = UUID()
        let legacyPersistor = WorkspacePersistor(workspacesDir: tempDir)
        let legacyInboxURL = try seedLegacySettingsSidecars(
            workspaceId: workspaceId,
            legacyPersistor: legacyPersistor
        )
        makeStore().restore(for: workspaceId)
        try await scrubLegacySettingsSidecars(
            workspaceId: workspaceId,
            legacyPersistor: legacyPersistor,
            legacyInboxURL: legacyInboxURL
        )
        try FileManager.default.removeItem(at: settingsFileURL(for: workspaceId))

        let restoredEditorPreference = EditorPreferenceAtom()
        let restoredInboxPrefs = InboxNotificationPrefsAtom()
        makeStore(
            editorPreference: restoredEditorPreference,
            inboxPrefs: restoredInboxPrefs
        ).restore(for: workspaceId)

        #expect(restoredEditorPreference.bookmarkedEditorId == "cursor")
        #expect(restoredInboxPrefs.grouping == .byRepo)
        #expect(restoredInboxPrefs.sort == .oldestFirst)
        #expect(restoredInboxPrefs.bellEnabled)
    }

    @Test
    func restoreMissingSettingsFileRecoversValidLegacyInboxPreferenceFields() throws {
        let workspaceId = UUID()
        let legacyPersistor = WorkspacePersistor(workspacesDir: tempDir)
        let legacyInboxURL = legacyPersistor.notificationInboxFileURL(for: workspaceId)
        try Data(
            """
            {
                "schemaVersion": 3,
                "notifications": [],
                "prefs": {
                    "grouping": "not-a-group",
                    "sort": "oldestFirst",
                    "bellEnabled": true
                },
                "sidebarState": {
                    "collapsedGroups": []
                }
            }
            """.utf8
        ).write(to: legacyInboxURL, options: .atomic)
        let inboxPrefs = InboxNotificationPrefsAtom()

        makeStore(inboxPrefs: inboxPrefs).restore(for: workspaceId)

        #expect(inboxPrefs.grouping == .byTab)
        #expect(inboxPrefs.sort == .oldestFirst)
        #expect(inboxPrefs.bellEnabled)
    }

    @Test
    func restoreCorruptSettingsFileFallsBackToLegacySettingsSlices() throws {
        let workspaceId = UUID()
        try Data("not-json".utf8).write(to: settingsFileURL(for: workspaceId), options: .atomic)
        let store = makeStore()

        store.restore(for: workspaceId)

        #expect(FileManager.default.fileExists(atPath: settingsFileURL(for: workspaceId).path) == false)
    }

    @Test
    func flushWritesPrettySortedSettingsAndStripsUnknownKeys() throws {
        let workspaceId = UUID()
        let settingsURL = settingsFileURL(for: workspaceId)
        try Data(
            """
            {
              "unknown": true,
              "schemaVersion": 1,
              "workspaceId": "\(workspaceId.uuidString)",
              "editorChooser": {"bookmarkedEditorId": "vscode", "runtimePane": "bad"},
              "sidebar": {"checkoutColors": {"repo:old": "#111111"}, "unknown": true},
              "notifications": {"grouping": "byRepo", "sort": "newestFirst", "bellEnabled": true}
            }
            """.utf8
        ).write(to: settingsURL, options: .atomic)
        let editorPreference = EditorPreferenceAtom()
        let inboxPrefs = InboxNotificationPrefsAtom()
        let store = makeStore(
            editorPreference: editorPreference,
            inboxPrefs: inboxPrefs
        )

        store.restore(for: workspaceId)
        try store.flush(for: workspaceId)

        let rawSettings = try String(contentsOf: settingsURL, encoding: .utf8)
        #expect(rawSettings.contains("\n  \"editorChooser\""))
        #expect(!rawSettings.contains("\"unknown\""))
        #expect(!rawSettings.contains("runtimePane"))
        #expect(!rawSettings.contains("checkoutColors"))
        let editorChooserIndex = rawSettings.firstRange(of: "\"editorChooser\"")!.lowerBound
        let notificationsIndex = rawSettings.firstRange(of: "\"notifications\"")!.lowerBound
        let schemaVersionIndex = rawSettings.firstRange(of: "\"schemaVersion\"")!.lowerBound
        let sidebarIndex = rawSettings.firstRange(of: "\"sidebar\"")!.lowerBound
        let workspaceIdIndex = rawSettings.firstRange(of: "\"workspaceId\"")!.lowerBound
        #expect(editorChooserIndex < notificationsIndex)
        #expect(notificationsIndex < schemaVersionIndex)
        #expect(schemaVersionIndex < sidebarIndex)
        #expect(sidebarIndex < workspaceIdIndex)
    }

    @Test
    func editorChooserRuntimeStateIsNotWrittenToSettings() throws {
        let workspaceId = UUID()
        let editorPreference = EditorPreferenceAtom()
        let editorRuntime = EditorChooserRuntimeAtom()
        let editorChooser = EditorChooserState(
            preferenceAtom: editorPreference,
            runtimeAtom: editorRuntime
        )
        let store = makeStore(editorPreference: editorPreference)

        editorChooser.setBookmarkedEditor("cursor")
        editorChooser.setOpenEditorPane(UUID())
        editorChooser.setAvailableTargets(ExternalEditorTarget.curatedOrder)

        try store.flush(for: workspaceId)

        let rawSettings = try String(contentsOf: settingsFileURL(for: workspaceId), encoding: .utf8)
        #expect(rawSettings.contains("\"bookmarkedEditorId\" : \"cursor\""))
        #expect(!rawSettings.contains("openForPaneId"))
        #expect(!rawSettings.contains("availableTargets"))
    }

    @Test
    func restoreCorruptSettingsFileQuarantinesAndDoesNotDeleteLocalDatabase() throws {
        let workspaceId = UUID()
        let settingsURL = settingsFileURL(for: workspaceId)
        let localURL = tempDir.appending(path: "\(workspaceId.uuidString).local.sqlite")
        try Data("not-json".utf8).write(to: settingsURL, options: .atomic)
        try Data("local-db-placeholder".utf8).write(to: localURL, options: .atomic)
        var reportedRecovery: PersistenceRecoveryEvent?

        let editorPreference = EditorPreferenceAtom()
        let inboxPrefs = InboxNotificationPrefsAtom()
        editorPreference.setBookmarkedEditor("cursor")
        inboxPrefs.setBellEnabled(true)
        makeStore(
            editorPreference: editorPreference,
            inboxPrefs: inboxPrefs,
            recoveryReporter: { reportedRecovery = $0 }
        ).restore(for: workspaceId)

        #expect(editorPreference.bookmarkedEditorId == nil)
        #expect(!inboxPrefs.bellEnabled)
        #expect(FileManager.default.fileExists(atPath: localURL.path))
        #expect(reportedRecovery?.store == .workspaceSettings)
        #expect(reportedRecovery?.workspaceId == workspaceId)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)

        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("\(workspaceId.uuidString).settings.corrupt-")
        }
        #expect(quarantinedFiles.count == 1)
    }

    @Test
    func restoreSettingsFileWithMismatchedWorkspaceIdQuarantinesAndResets() throws {
        let workspaceId = UUID()
        let otherWorkspaceId = UUID()
        let settingsURL = settingsFileURL(for: workspaceId)
        try Data(
            """
            {
              "schemaVersion": 1,
              "workspaceId": "\(otherWorkspaceId.uuidString)",
              "editorChooser": {"bookmarkedEditorId": "cursor"},
              "sidebar": {"checkoutColors": {"repo:agent-studio": "#22cc88"}},
              "notifications": {"grouping": "byRepo", "sort": "oldestFirst", "bellEnabled": true}
            }
            """.utf8
        ).write(to: settingsURL, options: .atomic)
        var reportedRecovery: PersistenceRecoveryEvent?

        let editorPreference = EditorPreferenceAtom()
        let inboxPrefs = InboxNotificationPrefsAtom()
        makeStore(
            editorPreference: editorPreference,
            inboxPrefs: inboxPrefs,
            recoveryReporter: { reportedRecovery = $0 }
        ).restore(for: workspaceId)

        #expect(editorPreference.bookmarkedEditorId == nil)
        #expect(inboxPrefs.grouping == .byTab)
        #expect(inboxPrefs.sort == .newestFirst)
        #expect(!inboxPrefs.bellEnabled)
        #expect(reportedRecovery?.store == .workspaceSettings)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)
        #expect(!FileManager.default.fileExists(atPath: settingsURL.path))
    }

    @Test
    func restoreCorruptSettingsFileReportsQuarantineFailedWhenMoveFails() throws {
        let workspaceId = UUID()
        let settingsURL = settingsFileURL(for: workspaceId)
        try Data("not-json".utf8).write(to: settingsURL, options: .atomic)
        var reportedRecovery: PersistenceRecoveryEvent?

        makeStore(
            quarantineCorruptSettingsFile: { _ in nil },
            recoveryReporter: { reportedRecovery = $0 }
        ).restore(for: workspaceId)

        #expect(reportedRecovery?.store == .workspaceSettings)
        #expect(reportedRecovery?.workspaceId == workspaceId)
        #expect(reportedRecovery?.recovery == .quarantineFailed)
        #expect(reportedRecovery?.quarantinedFilename == nil)
        #expect(FileManager.default.fileExists(atPath: settingsURL.path))
    }

    @Test
    func autosaveObservationStateIsExplicitlyArmed() {
        let workspaceId = UUID()
        let store = makeStore()

        #expect(store.isAutosaveObservationActive == false)
        store.restore(for: workspaceId)
        #expect(store.isAutosaveObservationActive == false)
        store.startObserving()
        #expect(store.isAutosaveObservationActive == true)
    }

    @Test
    func observedSettingsMutationsAutosaveAllSettingsSlices() async throws {
        let workspaceId = UUID()
        let editorPreference = EditorPreferenceAtom()
        let inboxPrefs = InboxNotificationPrefsAtom()
        let clock = TestPushClock()
        let store = makeStore(
            editorPreference: editorPreference,
            inboxPrefs: inboxPrefs,
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )

        store.restore(for: workspaceId)
        store.startObserving()
        editorPreference.setBookmarkedEditor("cursor")
        inboxPrefs.setGrouping(.byRepo)
        inboxPrefs.setSort(.oldestFirst)
        inboxPrefs.setBellEnabled(true)
        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(10))
        await store.waitForPendingAutosave()

        guard let settings = readSettingsJSON(for: workspaceId) else {
            Issue.record("Expected settings autosave to write JSON")
            return
        }
        let editorChooser = settings["editorChooser"] as? [String: Any]
        let sidebar = settings["sidebar"] as? [String: Any]
        let notifications = settings["notifications"] as? [String: Any]
        #expect(editorChooser?["bookmarkedEditorId"] as? String == "cursor")
        #expect(sidebar?["checkoutColors"] == nil)
        #expect(notifications?["grouping"] as? String == "byRepo")
        #expect(notifications?["sort"] as? String == "oldestFirst")
        #expect(notifications?["bellEnabled"] as? Bool == true)
    }

    @Test
    func restoreCancelsPendingDebouncedSaveForPreviousWorkspace() async throws {
        let workspaceAId = UUID()
        let workspaceBId = UUID()
        let editorPreference = EditorPreferenceAtom()
        let clock = TestPushClock()
        let store = makeStore(
            editorPreference: editorPreference,
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )

        store.restore(for: workspaceAId)
        store.startObserving()
        editorPreference.setBookmarkedEditor("workspace-a")
        await clock.waitForPendingSleepCount()
        store.restore(for: workspaceBId)
        clock.advance(by: .milliseconds(10))

        #expect(!FileManager.default.fileExists(atPath: settingsFileURL(for: workspaceAId).path))
    }

    @Test
    func flushFailureReportsSaveFailedRecovery() {
        let workspaceId = UUID()
        let blockedDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: "workspace-settings-blocked-\(UUID().uuidString)")
        try? Data("not-a-directory".utf8).write(to: blockedDirectoryURL, options: .atomic)
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = makeStore(
            workspacesDir: blockedDirectoryURL,
            recoveryReporter: { reportedRecovery = $0 }
        )

        #expect(throws: Error.self) {
            try store.flush(for: workspaceId)
        }

        #expect(reportedRecovery?.store == .workspaceSettings)
        #expect(reportedRecovery?.workspaceId == workspaceId)
        #expect(reportedRecovery?.recovery == .saveFailed)
    }

    private func makeStore(
        editorPreference: EditorPreferenceAtom = EditorPreferenceAtom(),
        inboxPrefs: InboxNotificationPrefsAtom = InboxNotificationPrefsAtom(),
        workspacesDir: URL? = nil,
        legacyPersistor: WorkspacePersistor? = nil,
        persistDebounceDuration: Duration = .zero,
        clock: (any Clock<Duration> & Sendable)? = ContinuousClock(),
        quarantineCorruptSettingsFile: (@MainActor (UUID) -> URL?)? = nil,
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) -> WorkspaceSettingsStore {
        WorkspaceSettingsStore(
            editorPreferenceAtom: editorPreference,
            inboxNotificationPrefsAtom: inboxPrefs,
            workspacesDir: workspacesDir ?? tempDir,
            legacyPersistor: legacyPersistor,
            persistDebounceDuration: persistDebounceDuration,
            clock: clock,
            quarantineCorruptSettingsFile: quarantineCorruptSettingsFile,
            recoveryReporter: recoveryReporter
        )
    }

    private func settingsFileURL(for workspaceId: UUID) -> URL {
        tempDir.appending(path: "\(workspaceId.uuidString).settings.json")
    }

    private func readSettingsJSON(for workspaceId: UUID) -> [String: Any]? {
        let settingsURL = settingsFileURL(for: workspaceId)
        guard
            let data = try? Data(contentsOf: settingsURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private func seedLegacySettingsSidecars(
        workspaceId: UUID,
        legacyPersistor: WorkspacePersistor
    ) throws -> URL {
        try legacyPersistor.saveUI(
            .init(
                workspaceId: workspaceId,
                editorChooserState: .init(bookmarkedEditorId: "cursor")
            )
        )
        let legacyInboxURL = legacyPersistor.notificationInboxFileURL(for: workspaceId)
        try Data(
            """
            {
                "schemaVersion": 3,
                "notifications": [],
                "prefs": {
                    "grouping": "byRepo",
                    "sort": "oldestFirst",
                    "bellEnabled": true
                },
                "sidebarState": {
                    "collapsedGroups": []
                }
            }
            """.utf8
        ).write(to: legacyInboxURL, options: .atomic)
        return legacyInboxURL
    }

    private func scrubLegacySettingsSidecars(
        workspaceId: UUID,
        legacyPersistor: WorkspacePersistor,
        legacyInboxURL: URL
    ) async throws {
        try UIStateStore(
            atom: WorkspaceSidebarState(),
            persistor: legacyPersistor
        ).flush(for: workspaceId)
        try SidebarCacheStore(
            atom: SidebarCacheState(),
            persistor: legacyPersistor
        ).flush(for: workspaceId)
        try await InboxNotificationStore(
            inboxAtom: InboxNotificationAtom(),
            prefsAtom: InboxNotificationPrefsAtom(),
            fileURL: legacyInboxURL
        ).save()
    }
}
