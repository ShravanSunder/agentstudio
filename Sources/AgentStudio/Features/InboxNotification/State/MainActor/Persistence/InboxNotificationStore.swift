import Foundation
import os.log

private let inboxNotificationStoreLogger = Logger(
    subsystem: "com.agentstudio",
    category: "InboxNotificationStore"
)

/// Persistence wrapper over the notification-inbox feature atoms.
///
/// One store owns one JSON file that persists both the inbox log and inbox
/// preferences together.
@MainActor
final class InboxNotificationStore {
    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom

    private let fileURL: URL
    private let clock: any Clock<Duration>
    private let debounceDuration: Duration
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?

    init(
        inboxAtom: InboxNotificationAtom,
        prefsAtom: InboxNotificationPrefsAtom,
        fileURL: URL,
        clock: any Clock<Duration> = ContinuousClock(),
        debounceDuration: Duration = .milliseconds(500),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.inboxAtom = inboxAtom
        self.prefsAtom = prefsAtom
        self.fileURL = fileURL
        self.clock = clock
        self.debounceDuration = debounceDuration
        self.recoveryReporter = recoveryReporter
    }

    private struct Payload: Codable {
        static let currentSchemaVersion = 1

        var schemaVersion: Int = currentSchemaVersion
        var notifications: [InboxNotification]
        var prefs: Prefs

        struct Prefs: Codable {
            var grouping: InboxNotificationGrouping = .none
            var sort: InboxNotificationSort = .newestFirst
            var bellEnabled: Bool = false

            private enum CodingKeys: String, CodingKey {
                case grouping
                case sort
                case bellEnabled
            }

            init(
                grouping: InboxNotificationGrouping = .none,
                sort: InboxNotificationSort = .newestFirst,
                bellEnabled: Bool = false
            ) {
                self.grouping = grouping
                self.sort = sort
                self.bellEnabled = bellEnabled
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.grouping =
                    (try? container.decodeIfPresent(InboxNotificationGrouping.self, forKey: .grouping))
                    ?? .none
                self.sort =
                    (try? container.decodeIfPresent(InboxNotificationSort.self, forKey: .sort))
                    ?? .newestFirst
                self.bellEnabled =
                    (try? container.decodeIfPresent(Bool.self, forKey: .bellEnabled))
                    ?? false
            }
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case notifications
            case prefs
        }

        init(
            schemaVersion: Int = 1,
            notifications: [InboxNotification],
            prefs: Prefs
        ) {
            self.schemaVersion = schemaVersion
            self.notifications = notifications
            self.prefs = prefs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            guard decodedSchemaVersion == Self.currentSchemaVersion else {
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
            self.prefs =
                (try? container.decodeIfPresent(Prefs.self, forKey: .prefs))
                ?? .init()
        }
    }

    func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

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
                    recovery: .quarantinedAndReset,
                    quarantinedFilename: quarantinedURL?.lastPathComponent
                )
            )
            throw error
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
                    recovery: .quarantinedAndReset,
                    quarantinedFilename: quarantinedURL?.lastPathComponent
                )
            )
            throw error
        }

        inboxAtom.replaceAll(payload.notifications)
        prefsAtom.setGrouping(payload.prefs.grouping)
        prefsAtom.setSort(payload.prefs.sort)
        prefsAtom.setBellEnabled(payload.prefs.bellEnabled)
    }

    func save() async throws {
        try flush()
    }

    func flush() throws {
        let payload = Payload(
            schemaVersion: Payload.currentSchemaVersion,
            notifications: inboxAtom.notifications,
            prefs: .init(
                grouping: prefsAtom.grouping,
                sort: prefsAtom.sort,
                bellEnabled: prefsAtom.bellEnabled
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    func scheduleDebouncedSave() {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await clock.sleep(for: debounceDuration)
            } catch is CancellationError {
                return
            } catch {
                inboxNotificationStoreLogger.error(
                    "Inbox notification debounce failed; saving immediately: \(error)"
                )
            }
            guard !Task.isCancelled else { return }
            do {
                try await save()
            } catch {
                inboxNotificationStoreLogger.error("Inbox notification save failed: \(error)")
            }
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
}
