import Foundation
import Observation
import os.log

private let workspaceSettingsStoreLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspaceSettingsStore"
)

@MainActor
final class WorkspaceSettingsStore {
    private let editorPreferenceAtom: EditorPreferenceAtom
    private let sidebarCheckoutColorAtom: SidebarCheckoutColorAtom
    private let inboxNotificationPrefsAtom: InboxNotificationPrefsAtom
    private let workspacesDir: URL
    private let legacyPersistor: WorkspacePersistor
    private let persistDebounceDuration: Duration
    private let clock: any Clock<Duration>
    private let recoveryReporter: PersistenceRecoveryReporter?
    private let quarantineCorruptSettingsFileOverride: (@MainActor (UUID) -> URL?)?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingSettings = false
    private var isRestoringSettings = false
    private var activeWorkspaceId: UUID?
    private(set) var canArchiveLegacySettingsFiles = true

    var isAutosaveObservationActive: Bool {
        isObservingSettings
    }

    init(
        editorPreferenceAtom: EditorPreferenceAtom,
        sidebarCheckoutColorAtom: SidebarCheckoutColorAtom,
        inboxNotificationPrefsAtom: InboxNotificationPrefsAtom,
        workspacesDir: URL = AppDataPaths.workspacesDirectory(),
        legacyPersistor: WorkspacePersistor? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock(),
        quarantineCorruptSettingsFile: (@MainActor (UUID) -> URL?)? = nil,
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.editorPreferenceAtom = editorPreferenceAtom
        self.sidebarCheckoutColorAtom = sidebarCheckoutColorAtom
        self.inboxNotificationPrefsAtom = inboxNotificationPrefsAtom
        self.workspacesDir = workspacesDir
        self.legacyPersistor = legacyPersistor ?? WorkspacePersistor(workspacesDir: workspacesDir)
        self.persistDebounceDuration = persistDebounceDuration
        self.clock = clock
        self.quarantineCorruptSettingsFileOverride = quarantineCorruptSettingsFile
        self.recoveryReporter = recoveryReporter
    }

    func startObserving() {
        observeSettings()
    }

    func restore(for workspaceId: UUID) {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId
        canArchiveLegacySettingsFiles = true
        let settingsURL = settingsFileURL(for: workspaceId)
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            if restoreFromBackupIfAvailable(for: workspaceId) {
                return
            }
            hydrateLegacyOrDefaults(for: workspaceId)
            return
        }

        do {
            let payload = try decodePayload(from: settingsURL)
            try validatePayload(payload, for: workspaceId)
            isRestoringSettings = true
            hydrate(from: payload)
            isRestoringSettings = false
            materializeSettingsBackup(payload, for: workspaceId)
        } catch {
            let quarantinedURL = quarantineCorruptSettingsFile(for: workspaceId)
            workspaceSettingsStoreLogger.warning("Workspace settings file corrupt: \(error)")
            let didRestoreFromBackup = restoreFromBackupIfAvailable(for: workspaceId)
            if !didRestoreFromBackup {
                hydrateLegacyOrDefaults(for: workspaceId)
            }
            recoveryReporter?(
                .init(
                    store: .workspaceSettings,
                    workspaceId: workspaceId,
                    recovery: quarantinedURL == nil ? .quarantineFailed : .quarantinedAndReset,
                    quarantinedFilename: quarantinedURL?.lastPathComponent
                )
            )
        }
    }

    func flush(for workspaceId: UUID) throws {
        activeWorkspaceId = workspaceId
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        try persistNow(for: workspaceId)
    }

    private func observeSettings() {
        guard !isObservingSettings else { return }
        isObservingSettings = true
        withObservationTracking {
            _ = editorPreferenceAtom.bookmarkedEditorId
            _ = sidebarCheckoutColorAtom.checkoutColors
            _ = inboxNotificationPrefsAtom.grouping
            _ = inboxNotificationPrefsAtom.sort
            _ = inboxNotificationPrefsAtom.bellEnabled
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let shouldIgnore = self.isRestoringSettings
                self.isObservingSettings = false
                self.observeSettings()
                guard !shouldIgnore else { return }
                self.schedulePersist()
            }
        }
    }

    private func schedulePersist() {
        guard let workspaceId = activeWorkspaceId else { return }
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.clock.sleep(for: self.persistDebounceDuration)
            guard !Task.isCancelled else { return }
            do {
                try self.persistNow(for: workspaceId)
            } catch {
                workspaceSettingsStoreLogger.warning(
                    "Workspace settings autosave failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func persistNow(for workspaceId: UUID) throws {
        do {
            try persistPayload(currentPayload(workspaceId: workspaceId), for: workspaceId)
        } catch {
            recoveryReporter?(.init(store: .workspaceSettings, workspaceId: workspaceId, recovery: .saveFailed))
            throw error
        }
    }

    private func currentPayload(workspaceId: UUID) -> WorkspaceSettingsPayload {
        .init(
            workspaceId: workspaceId,
            editorChooser: .init(bookmarkedEditorId: editorPreferenceAtom.bookmarkedEditorId),
            sidebar: .init(checkoutColors: sidebarCheckoutColorAtom.checkoutColors),
            notifications: .init(
                grouping: inboxNotificationPrefsAtom.grouping,
                sort: inboxNotificationPrefsAtom.sort,
                bellEnabled: inboxNotificationPrefsAtom.bellEnabled
            )
        )
    }

    private func hydrate(from payload: WorkspaceSettingsPayload) {
        editorPreferenceAtom.hydrate(bookmarkedEditorId: payload.editorChooser.bookmarkedEditorId)
        sidebarCheckoutColorAtom.hydrate(checkoutColors: payload.sidebar.checkoutColors)
        inboxNotificationPrefsAtom.setGrouping(payload.notifications.grouping)
        inboxNotificationPrefsAtom.setSort(payload.notifications.sort)
        inboxNotificationPrefsAtom.setBellEnabled(payload.notifications.bellEnabled)
    }

    private func hydrateDefaults() {
        editorPreferenceAtom.clear()
        sidebarCheckoutColorAtom.clear()
        inboxNotificationPrefsAtom.setGrouping(.byTab)
        inboxNotificationPrefsAtom.setSort(.newestFirst)
        inboxNotificationPrefsAtom.setBellEnabled(false)
    }

    private func hydrateLegacyOrDefaults(for workspaceId: UUID) {
        let legacyImport = legacyPayloadOrDefaults(for: workspaceId)
        isRestoringSettings = true
        hydrate(from: legacyImport.payload)
        isRestoringSettings = false
        canArchiveLegacySettingsFiles = materializeLegacySettingsIfNeeded(legacyImport, for: workspaceId)
    }

    @discardableResult
    private func materializeLegacySettingsIfNeeded(
        _ legacyImport: LegacySettingsImport,
        for workspaceId: UUID
    ) -> Bool {
        guard legacyImport.importedAnySlice else { return true }
        do {
            try persistNow(for: workspaceId)
            return true
        } catch {
            workspaceSettingsStoreLogger.warning(
                "Workspace settings legacy import materialization failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    private func materializeSettingsBackup(
        _ payload: WorkspaceSettingsPayload,
        for workspaceId: UUID
    ) {
        do {
            try persistBackupPayload(payload, for: workspaceId)
        } catch {
            workspaceSettingsStoreLogger.warning(
                "Workspace settings backup materialization failed: \(error.localizedDescription)"
            )
        }
    }

    private func restoreFromBackupIfAvailable(for workspaceId: UUID) -> Bool {
        let backupURL = settingsBackupFileURL(for: workspaceId)
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return false }
        do {
            let payload = try decodePayload(from: backupURL)
            try validatePayload(payload, for: workspaceId)
            isRestoringSettings = true
            hydrate(from: payload)
            isRestoringSettings = false
            do {
                try persistPayload(payload, for: workspaceId)
            } catch {
                workspaceSettingsStoreLogger.warning(
                    "Workspace settings primary restore from backup failed: \(error.localizedDescription)"
                )
            }
            return true
        } catch {
            isRestoringSettings = false
            workspaceSettingsStoreLogger.warning(
                "Workspace settings backup restore skipped: \(error.localizedDescription)"
            )
            return false
        }
    }

    private func legacyPayloadOrDefaults(for workspaceId: UUID) -> LegacySettingsImport {
        var payload = WorkspaceSettingsPayload(workspaceId: workspaceId)
        var importedAnySlice = false
        if case .loaded(let uiState) = legacyPersistor.loadUI(for: workspaceId),
            uiState.workspaceId == workspaceId
        {
            payload.editorChooser.bookmarkedEditorId = uiState.editorChooserState.bookmarkedEditorId
            importedAnySlice = true
        }
        if case .loaded(let sidebarCache) = legacyPersistor.loadSidebarCache(for: workspaceId),
            sidebarCache.workspaceId == workspaceId
        {
            payload.sidebar.checkoutColors = sidebarCache.checkoutColors
            importedAnySlice = true
        }
        if let legacyNotificationPrefs = loadLegacyNotificationPrefs(for: workspaceId) {
            payload.notifications = legacyNotificationPrefs
            importedAnySlice = true
        }
        return .init(payload: payload, importedAnySlice: importedAnySlice)
    }

    private func loadLegacyNotificationPrefs(for workspaceId: UUID) -> WorkspaceSettingsPayload.Notifications? {
        let inboxURL = legacyPersistor.notificationInboxFileURL(for: workspaceId)
        guard FileManager.default.fileExists(atPath: inboxURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: inboxURL)
            let payload = try JSONDecoder().decode(LegacyInboxSettingsPayload.self, from: data)
            return payload.prefs.map {
                .init(grouping: $0.grouping, sort: $0.sort, bellEnabled: $0.bellEnabled)
            }
        } catch {
            workspaceSettingsStoreLogger.warning(
                "Legacy inbox settings import skipped for \(workspaceId.uuidString): \(error.localizedDescription)"
            )
            return nil
        }
    }

    private func decodePayload(from url: URL) throws -> WorkspaceSettingsPayload {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WorkspaceSettingsPayload.self, from: data)
    }

    private func persistPayload(_ payload: WorkspaceSettingsPayload, for workspaceId: UUID) throws {
        try FileManager.default.createDirectory(at: workspacesDir, withIntermediateDirectories: true)
        let data = try encodePayload(payload)
        try data.write(to: settingsBackupFileURL(for: workspaceId), options: .atomic)
        try data.write(to: settingsFileURL(for: workspaceId), options: .atomic)
    }

    private func persistBackupPayload(_ payload: WorkspaceSettingsPayload, for workspaceId: UUID) throws {
        try FileManager.default.createDirectory(at: workspacesDir, withIntermediateDirectories: true)
        try encodePayload(payload).write(to: settingsBackupFileURL(for: workspaceId), options: .atomic)
    }

    private func encodePayload(_ payload: WorkspaceSettingsPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    private func validatePayload(_ payload: WorkspaceSettingsPayload, for workspaceId: UUID) throws {
        guard payload.workspaceId == workspaceId else {
            throw WorkspaceSettingsStoreError.workspaceIdMismatch(
                expected: workspaceId,
                actual: payload.workspaceId
            )
        }
    }

    @discardableResult
    private func quarantineCorruptSettingsFile(for workspaceId: UUID) -> URL? {
        if let quarantineCorruptSettingsFileOverride {
            return quarantineCorruptSettingsFileOverride(workspaceId)
        }
        let sourceURL = settingsFileURL(for: workspaceId)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return nil
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let quarantinedFilename = "\(workspaceId.uuidString).settings.corrupt-\(timestamp).json"
        let quarantinedURL = workspacesDir.appending(path: quarantinedFilename)
        do {
            try FileManager.default.moveItem(at: sourceURL, to: quarantinedURL)
            return quarantinedURL
        } catch {
            workspaceSettingsStoreLogger.error(
                "Failed to quarantine corrupt workspace settings file \(sourceURL.lastPathComponent): \(error)"
            )
            return nil
        }
    }

    private func settingsFileURL(for workspaceId: UUID) -> URL {
        workspacesDir.appending(path: "\(workspaceId.uuidString).settings.json")
    }

    private func settingsBackupFileURL(for workspaceId: UUID) -> URL {
        workspacesDir.appending(path: "\(workspaceId.uuidString).settings.backup.json")
    }
}

private enum WorkspaceSettingsStoreError: Error {
    case workspaceIdMismatch(expected: UUID, actual: UUID)
}

private struct LegacySettingsImport {
    var payload: WorkspaceSettingsPayload
    var importedAnySlice: Bool
}

private struct LegacyInboxSettingsPayload: Decodable {
    struct Prefs: Decodable {
        var grouping: InboxNotificationGrouping = .byTab
        var sort: InboxNotificationSort = .newestFirst
        var bellEnabled: Bool = false

        private enum CodingKeys: String, CodingKey {
            case grouping
            case sort
            case bellEnabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.grouping = decodeRecoverableLegacyInboxPreferenceField(
                InboxNotificationGrouping.self,
                from: container,
                forKey: .grouping,
                default: .byTab
            )
            self.sort = decodeRecoverableLegacyInboxPreferenceField(
                InboxNotificationSort.self,
                from: container,
                forKey: .sort,
                default: .newestFirst
            )
            self.bellEnabled = decodeRecoverableLegacyInboxPreferenceField(
                Bool.self,
                from: container,
                forKey: .bellEnabled,
                default: false
            )
        }
    }

    var prefs: Prefs?
}

private func decodeRecoverableLegacyInboxPreferenceField<Key: CodingKey, Value: Decodable>(
    _ type: Value.Type,
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key,
    default defaultValue: @autoclosure () -> Value
) -> Value {
    do {
        if let value = try container.decodeIfPresent(type, forKey: key) {
            return value
        }
    } catch {
        workspaceSettingsStoreLogger.warning(
            "Legacy inbox preference invalid field \(key.stringValue, privacy: .public); using default"
        )
        return defaultValue()
    }

    workspaceSettingsStoreLogger.warning(
        "Legacy inbox preference missing field \(key.stringValue, privacy: .public); using default"
    )
    return defaultValue()
}

private struct WorkspaceSettingsPayload: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var workspaceId: UUID
    var editorChooser: EditorChooser
    var sidebar: Sidebar
    var notifications: Notifications

    init(
        workspaceId: UUID,
        editorChooser: EditorChooser = .init(),
        sidebar: Sidebar = .init(),
        notifications: Notifications = .init()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.workspaceId = workspaceId
        self.editorChooser = editorChooser
        self.sidebar = sidebar
        self.notifications = notifications
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case workspaceId
        case editorChooser
        case sidebar
        case notifications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Workspace settings schemaVersion \(decodedSchemaVersion) is unsupported"
            )
        }
        self.schemaVersion = decodedSchemaVersion
        self.workspaceId = try container.decode(UUID.self, forKey: .workspaceId)
        self.editorChooser = try container.decodeIfPresent(EditorChooser.self, forKey: .editorChooser) ?? .init()
        self.sidebar = try container.decodeIfPresent(Sidebar.self, forKey: .sidebar) ?? .init()
        self.notifications = try container.decodeIfPresent(Notifications.self, forKey: .notifications) ?? .init()
    }

    struct EditorChooser: Codable {
        var bookmarkedEditorId: EditorTargetId?
    }

    struct Sidebar: Codable {
        var checkoutColors: [SidebarCheckoutColorKey: String]

        init(checkoutColors: [SidebarCheckoutColorKey: String] = [:]) {
            self.checkoutColors = checkoutColors
        }

        private enum CodingKeys: String, CodingKey {
            case checkoutColors
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawCheckoutColors = try container.decodeIfPresent([String: String].self, forKey: .checkoutColors) ?? [:]
            self.checkoutColors = Dictionary(
                uniqueKeysWithValues: rawCheckoutColors.map { key, value in
                    (SidebarCheckoutColorKey(key), value)
                }
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(
                Dictionary(uniqueKeysWithValues: checkoutColors.map { key, value in (key.rawValue, value) }),
                forKey: .checkoutColors
            )
        }
    }

    struct Notifications: Codable {
        var grouping: InboxNotificationGrouping
        var sort: InboxNotificationSort
        var bellEnabled: Bool

        init(
            grouping: InboxNotificationGrouping = .byTab,
            sort: InboxNotificationSort = .newestFirst,
            bellEnabled: Bool = false
        ) {
            self.grouping = grouping
            self.sort = sort
            self.bellEnabled = bellEnabled
        }
    }
}
