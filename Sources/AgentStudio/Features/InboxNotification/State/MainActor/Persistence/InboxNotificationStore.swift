import Foundation
import os.log

private let inboxNotificationStoreLogger = Logger(
    subsystem: "com.agentstudio",
    category: "InboxNotificationStore"
)

/// Persistence wrapper over the notification-inbox feature atoms.
///
/// Persists the inbox log and collapsed sidebar groups.
///
/// Preferences are settings-owned, and pending sidebar filters are runtime-only.
@MainActor
final class InboxNotificationStore {
    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
    let sidebarState: InboxSidebarState

    private let fileURL: URL
    private let delay: AsyncDelay
    private let debounceDuration: Duration
    private let recoveryReporter: PersistenceRecoveryReporter?
    private let sqliteAdapter: InboxNotificationSQLiteDatastoreAdapter?
    private let allowLegacyFilePersistence: Bool
    private let allowLegacyFileImport: Bool
    private var debouncedSaveTask: Task<Void, Never>?

    enum LoadOutcome: Equatable {
        case sqliteSnapshot
        case materializedLegacySQLiteSnapshot
        case legacyFileImportedIntoSQLite
        case legacyFile
        case missing
        case legacyImportBlockedReset

        var hasMaterializedLegacyFile: Bool {
            switch self {
            case .materializedLegacySQLiteSnapshot, .legacyFileImportedIntoSQLite:
                return true
            case .sqliteSnapshot, .legacyFile, .missing, .legacyImportBlockedReset:
                return false
            }
        }
    }

    struct SQLiteSnapshot: Equatable, Sendable {
        var notifications: [InboxNotification]
        var collapsedGroups: Set<InboxNotificationGroupKey>
        var markLegacyImport: Bool
    }

    struct SQLiteLoadSnapshot: Equatable, Sendable {
        var notifications: [InboxNotification]
        var collapsedGroups: Set<InboxNotificationGroupKey>
        var hasPersistedState: Bool
        var hasMaterializedLegacyImport: Bool
    }

    init(
        inboxAtom: InboxNotificationAtom,
        prefsAtom: InboxNotificationPrefsAtom,
        sidebarState: InboxSidebarState = .init(),
        fileURL: URL,
        clock: (any Clock<Duration> & Sendable)? = nil,
        debounceDuration: Duration = .milliseconds(500),
        recoveryReporter: PersistenceRecoveryReporter? = nil,
        sqliteAdapter: InboxNotificationSQLiteDatastoreAdapter? = nil,
        allowLegacyFilePersistence: Bool = true,
        allowLegacyFileImport: Bool = true
    ) {
        self.inboxAtom = inboxAtom
        self.prefsAtom = prefsAtom
        self.sidebarState = sidebarState
        self.fileURL = fileURL
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
        self.debounceDuration = debounceDuration
        self.recoveryReporter = recoveryReporter
        self.sqliteAdapter = sqliteAdapter
        self.allowLegacyFilePersistence = allowLegacyFilePersistence
        self.allowLegacyFileImport = allowLegacyFileImport
    }

    private struct Payload: Codable {
        static let currentSchemaVersion = 3
        static let supportedSchemaVersions = 1...currentSchemaVersion

        var schemaVersion: Int = currentSchemaVersion
        var notifications: [InboxNotification]
        var prefs: Prefs
        var sidebarState: SidebarState

        struct Prefs: Codable {
            var grouping: InboxNotificationGrouping = .byTab
            var sort: InboxNotificationSort = .newestFirst
            var bellEnabled: Bool = false

            private enum CodingKeys: String, CodingKey {
                case grouping
                case sort
                case bellEnabled
            }

            init(
                grouping: InboxNotificationGrouping = .byTab,
                sort: InboxNotificationSort = .newestFirst,
                bellEnabled: Bool = false
            ) {
                self.grouping = grouping
                self.sort = sort
                self.bellEnabled = bellEnabled
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.grouping = decodeRecoverablePreferenceField(
                    InboxNotificationGrouping.self,
                    from: container,
                    forKey: .grouping,
                    default: .byTab
                )
                self.sort = decodeRecoverablePreferenceField(
                    InboxNotificationSort.self,
                    from: container,
                    forKey: .sort,
                    default: .newestFirst
                )
                self.bellEnabled = decodeRecoverablePreferenceField(
                    Bool.self,
                    from: container,
                    forKey: .bellEnabled,
                    default: false
                )
            }
        }

        struct SidebarState: Codable {
            var collapsedGroups: Set<InboxNotificationGroupKey> = []
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case notifications
            case prefs
            case sidebarState
        }

        init(
            schemaVersion: Int = currentSchemaVersion,
            notifications: [InboxNotification],
            prefs: Prefs,
            sidebarState: SidebarState
        ) {
            self.schemaVersion = schemaVersion
            self.notifications = notifications
            self.prefs = prefs
            self.sidebarState = sidebarState
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            guard Self.supportedSchemaVersions.contains(decodedSchemaVersion) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion,
                    in: container,
                    debugDescription: "Inbox notification schemaVersion \(decodedSchemaVersion) is unsupported"
                )
            }
            self.schemaVersion = decodedSchemaVersion
            if container.contains(.notifications) {
                self.notifications = try container.decode([InboxNotification].self, forKey: .notifications)
            } else {
                self.notifications = []
            }
            self.prefs = decodeRecoverablePayloadField(
                Prefs.self,
                from: container,
                forKey: .prefs,
                default: .init()
            )
            self.sidebarState = decodeRecoverablePayloadField(
                SidebarState.self,
                from: container,
                forKey: .sidebarState,
                default: .init()
            )
        }
    }

    @discardableResult
    func load() throws -> LoadOutcome {
        guard sqliteAdapter == nil else {
            assertionFailure("Use await loadAsync() when SQLite datastore is enabled")
            return .missing
        }

        guard allowLegacyFilePersistence else { return .missing }
        guard let payload = loadLegacyPayloadFromDisk() else { return .missing }
        apply(payload)
        return .legacyFile
    }

    @discardableResult
    func loadAsync() async throws -> LoadOutcome {
        guard let sqliteAdapter else {
            return try load()
        }

        switch await sqliteAdapter.load() {
        case .loaded(let snapshot, let recoveryEvents):
            reportRecoveryEvents(recoveryEvents)
            if snapshot.hasPersistedState {
                apply(snapshot)
                return snapshot.hasMaterializedLegacyImport ? .materializedLegacySQLiteSnapshot : .sqliteSnapshot
            }
            guard allowLegacyFileImport else {
                inboxAtom.replaceAll([])
                sidebarState.hydrate(collapsedGroups: [])
                reportLoadFailed()
                return .legacyImportBlockedReset
            }
            guard let payload = loadLegacyPayloadFromDisk() else { return .missing }
            apply(payload)
            try await sqliteAdapter.save(currentSQLiteSnapshot(markLegacyImport: true))
            return .legacyFileImportedIntoSQLite
        case .unavailable(_, let recoveryEvents):
            reportRecoveryEvents(recoveryEvents)
            reportLoadFailed()
            throw InboxNotificationSQLiteDatastoreUnavailableError()
        }
    }

    private func loadLegacyPayloadFromDisk() -> Payload? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            let quarantinedURL = quarantineCorruptFile()
            inboxNotificationStoreLogger.warning("Inbox notification file unreadable, using defaults: \(error)")
            recoveryReporter?(
                .init(
                    store: .notificationInbox,
                    workspaceId: nil,
                    recovery: quarantinedURL == nil ? .quarantineFailed : .quarantinedAndReset,
                    quarantinedFilename: quarantinedURL?.lastPathComponent
                )
            )
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: Payload
        do {
            payload = try decoder.decode(Payload.self, from: data)
        } catch {
            let quarantinedURL = quarantineCorruptFile()
            inboxNotificationStoreLogger.warning("Inbox notification file corrupt, using defaults: \(error)")
            recoveryReporter?(
                .init(
                    store: .notificationInbox,
                    workspaceId: nil,
                    recovery: quarantinedURL == nil ? .quarantineFailed : .quarantinedAndReset,
                    quarantinedFilename: quarantinedURL?.lastPathComponent
                )
            )
            return nil
        }

        return payload
    }

    private func apply(_ payload: Payload) {
        inboxAtom.replaceAll(payload.notifications)
        sidebarState.hydrate(collapsedGroups: payload.sidebarState.collapsedGroups)
    }

    private func apply(_ snapshot: SQLiteLoadSnapshot) {
        inboxAtom.replaceAll(snapshot.notifications)
        sidebarState.hydrate(collapsedGroups: snapshot.collapsedGroups)
    }

    func save() async throws {
        cancelPendingDebouncedSave()
        try await persistCurrentPayloadAsync()
    }

    func flush() throws {
        guard sqliteAdapter == nil else {
            assertionFailure("Use await save() when SQLite datastore is enabled")
            throw LegacyFilePersistenceDisabledError()
        }
        cancelPendingDebouncedSave()
        try persistCurrentPayloadSynchronously()
    }

    private func encodedPayloadData() throws -> Data {
        let payload = Payload(
            schemaVersion: Payload.currentSchemaVersion,
            notifications: inboxAtom.notifications,
            prefs: .init(),
            sidebarState: .init(
                collapsedGroups: sidebarState.collapsedGroups
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    @concurrent
    nonisolated private static func writePayloadData(_ data: Data, to fileURL: URL) async throws {
        try writePayloadDataSynchronously(data, to: fileURL)
    }

    nonisolated private static func writePayloadDataSynchronously(_ data: Data, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    func scheduleDebouncedSave() {
        debouncedSaveTask?.cancel()
        let delay = self.delay
        let debounceDuration = self.debounceDuration
        debouncedSaveTask = Task { [weak self, delay, debounceDuration] in
            do {
                try await delay.wait(debounceDuration)
            } catch is CancellationError {
                return
            } catch {
                inboxNotificationStoreLogger.error(
                    "Inbox notification debounce failed; saving immediately: \(error)"
                )
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            do {
                try await persistCurrentPayloadAsync()
            } catch {
                inboxNotificationStoreLogger.error("Inbox notification save failed: \(error)")
            }
        }
    }

    private func cancelPendingDebouncedSave() {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
    }

    private func persistCurrentPayloadAsync() async throws {
        do {
            if let sqliteAdapter {
                try await sqliteAdapter.save(currentSQLiteSnapshot(markLegacyImport: false))
                return
            }
            guard allowLegacyFilePersistence else {
                throw LegacyFilePersistenceDisabledError()
            }
            let data = try encodedPayloadData()
            try await Self.writePayloadData(data, to: fileURL)
        } catch {
            reportSaveFailed()
            throw error
        }
    }

    private func persistCurrentPayloadSynchronously() throws {
        do {
            guard allowLegacyFilePersistence else {
                throw LegacyFilePersistenceDisabledError()
            }
            let data = try encodedPayloadData()
            try Self.writePayloadDataSynchronously(data, to: fileURL)
        } catch {
            reportSaveFailed()
            throw error
        }
    }

    @discardableResult
    private func quarantineCorruptFile() -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let quarantinedURL = fileURL.deletingLastPathComponent()
            .appending(path: "\(baseName).corrupt-\(timestamp).json")

        do {
            try FileManager.default.moveItem(at: fileURL, to: quarantinedURL)
            return quarantinedURL
        } catch {
            inboxNotificationStoreLogger.error(
                "Failed to quarantine corrupt inbox notification file \(self.fileURL.lastPathComponent): \(error)"
            )
            return nil
        }
    }

    private func currentSQLiteSnapshot(markLegacyImport: Bool) -> SQLiteSnapshot {
        .init(
            notifications: inboxAtom.notifications,
            collapsedGroups: sidebarState.collapsedGroups,
            markLegacyImport: markLegacyImport
        )
    }

    private func reportSaveFailed() {
        recoveryReporter?(
            .init(store: .notificationInbox, workspaceId: nil, recovery: .saveFailed)
        )
    }

    private func reportLoadFailed() {
        recoveryReporter?(
            .init(store: .notificationInbox, workspaceId: nil, recovery: .resetToDefaults)
        )
    }

    private func reportRecoveryEvents(_ recoveryEvents: [PersistenceRecoveryEvent]) {
        recoveryEvents.forEach { recoveryReporter?($0) }
    }
}

private struct LegacyFilePersistenceDisabledError: Error {}
private struct InboxNotificationSQLiteDatastoreUnavailableError: Error {}

private func decodeRecoverablePreferenceField<Key: CodingKey, Value: Decodable>(
    _ type: Value.Type,
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key,
    default defaultValue: @autoclosure () -> Value
) -> Value {
    decodeRecoverableInboxField(
        type,
        from: container,
        forKey: key,
        payloadName: "InboxNotificationPrefs",
        default: defaultValue()
    )
}

private func decodeRecoverablePayloadField<Key: CodingKey, Value: Decodable>(
    _ type: Value.Type,
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key,
    default defaultValue: @autoclosure () -> Value
) -> Value {
    decodeRecoverableInboxField(
        type,
        from: container,
        forKey: key,
        payloadName: "InboxNotificationPayload",
        default: defaultValue()
    )
}

private func decodeRecoverableInboxField<Key: CodingKey, Value: Decodable>(
    _ type: Value.Type,
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key,
    payloadName: String,
    default defaultValue: @autoclosure () -> Value
) -> Value {
    do {
        if let value = try container.decodeIfPresent(type, forKey: key) {
            return value
        }
    } catch {
        inboxNotificationStoreLogger.warning(
            "\(payloadName, privacy: .public) invalid field \(key.stringValue, privacy: .public); using default"
        )
        return defaultValue()
    }

    inboxNotificationStoreLogger.warning(
        "\(payloadName, privacy: .public) missing field \(key.stringValue, privacy: .public); using default"
    )
    return defaultValue()
}
