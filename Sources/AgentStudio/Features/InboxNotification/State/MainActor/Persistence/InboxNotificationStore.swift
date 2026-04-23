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
    private var debouncedSaveTask: Task<Void, Never>?

    init(
        inboxAtom: InboxNotificationAtom,
        prefsAtom: InboxNotificationPrefsAtom,
        fileURL: URL,
        clock: any Clock<Duration> = ContinuousClock(),
        debounceDuration: Duration = .milliseconds(500)
    ) {
        self.inboxAtom = inboxAtom
        self.prefsAtom = prefsAtom
        self.fileURL = fileURL
        self.clock = clock
        self.debounceDuration = debounceDuration
    }

    private struct Payload: Codable {
        var schemaVersion: Int = 1
        var notifications: [InboxNotification]
        var prefs: Prefs

        struct Prefs: Codable {
            var grouping: InboxNotificationGrouping
            var sort: InboxNotificationSort
            var bellEnabled: Bool
        }
    }

    func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: Payload
        do {
            payload = try decoder.decode(Payload.self, from: data)
        } catch {
            _ = quarantineCorruptFile()
            inboxNotificationStoreLogger.warning("Inbox notification file corrupt, using defaults: \(error)")
            throw error
        }

        inboxAtom.clearAll()
        for notification in payload.notifications {
            inboxAtom.append(notification)
        }
        prefsAtom.setGrouping(payload.prefs.grouping)
        prefsAtom.setSort(payload.prefs.sort)
        prefsAtom.setBellEnabled(payload.prefs.bellEnabled)
    }

    func save() async throws {
        try flush()
    }

    func flush() throws {
        let payload = Payload(
            schemaVersion: 1,
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
