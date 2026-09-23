import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// Where one pane's offline notification file lives. The pane construction
/// environment carries both values, so the CLI never derives the data root and
/// never links the App-side path resolver.
package struct PaneNotificationSpoolLocation: Equatable, Sendable {
    package let spoolDirectory: URL
    package let paneIdentifier: UUID

    package init(spoolDirectory: URL, paneIdentifier: UUID) {
        self.spoolDirectory = spoolDirectory
        self.paneIdentifier = paneIdentifier
    }

    /// A pane that was not constructed by Agent Studio has no owner-only file
    /// to append to, so its notification keeps the ordinary failure.
    package init?(environment: [String: String]) {
        guard let rawDirectory = environment["AGENTSTUDIO_IPC_SPOOL_DIR"],
            !rawDirectory.isEmpty,
            let rawPaneIdentifier = environment["AGENTSTUDIO_PANE_ID"],
            let paneIdentifier = UUID(uuidString: rawPaneIdentifier)
        else {
            return nil
        }
        self.init(
            spoolDirectory: URL(fileURLWithPath: rawDirectory, isDirectory: true),
            paneIdentifier: paneIdentifier
        )
    }

    package var notificationFileURL: URL {
        spoolDirectory.appendingPathComponent("\(paneIdentifier.uuidString).notifications.ndjson")
    }
}

/// An append that did not reach durable storage. The caller must report failure
/// rather than claim the notification was queued.
package struct PaneNotificationSpoolWriteError: Error, Equatable, Sendable {
    package enum Reason: String, Equatable, Sendable {
        case spoolDirectoryUnavailable
        case notificationFileUnavailable
        case exclusiveLockUnavailable
        case appendFailed
        case synchronizeFailed
        case lineEncodingFailed
        /// The spool file kept being replaced under this writer. Reporting it
        /// is the honest outcome: appending to the inode it locked would have
        /// succeeded, synchronized, and been read by nobody.
        case spoolFileRepeatedlyReplaced
    }

    package let reason: Reason
    package let errnoCode: Int32

    package init(reason: Reason, errnoCode: Int32 = 0) {
        self.reason = reason
        self.errnoCode = errnoCode
    }
}

extension IPCDescriptorClientFailure {
    /// Only an app that was never reached may queue. Authentication and protocol
    /// rejection prove the app answered, and every post-submission failure is
    /// uncertain rather than absent, so neither may become a second copy.
    package var permitsOfflineQueue: Bool {
        disposition == .endpointUnavailableBeforeSubmission
    }
}

/// What an unreachable app means for one parsed invocation.
package enum PaneNotificationOfflineOutcome: Equatable, Sendable {
    case queued(reply: String)
    case clearUnavailableWhileOffline
    case notQueued
}

/// Appends one already-encoded JSON-RPC request line to the pane's owner-only
/// notification file under an exclusive lock. The writer never encodes the
/// authentication frame and never sees the pane token.
package struct PaneNotificationSpoolWriter: Sendable {
    /// A drain replaces the file at most once per pass, so one reopen is
    /// already enough. The extra attempts cover a drain that starts again
    /// immediately; a writer that loses this many times in a row is not racing
    /// a drain, and reporting beats looping.
    private static let lockedAppendAttemptLimit = 3

    package init() {}

    /// Eligibility is descriptor metadata, not a method name: the clear verb
    /// shares `session.report` with the two eligible variants and must still be
    /// refused.
    package func offlineOutcome(for invocation: IPCDescriptorInvocation) -> PaneNotificationOfflineOutcome {
        guard case .model(let presentation) = invocation.presentation else { return .notQueued }
        guard presentation.isOfflineEligible else {
            return presentation.variant == .needsYouClear ? .clearUnavailableWhileOffline : .notQueued
        }
        guard let queuedReply = presentation.queuedReply else { return .notQueued }
        return .queued(reply: queuedReply)
    }

    package func append(
        requestLine: String,
        to location: PaneNotificationSpoolLocation,
        maximumLineBytes: Int
    ) throws {
        #if canImport(Darwin)
            let frame: Data
            do {
                frame = try NDJSONFrameEncoder.encode(requestLine, maxFrameBytes: maximumLineBytes)
            } catch {
                throw PaneNotificationSpoolWriteError(reason: .lineEncodingFailed)
            }
            try prepareSpoolDirectory(location.spoolDirectory)
            for _ in 0..<Self.lockedAppendAttemptLimit {
                if case .appended = try appendUnderExclusiveLock(frame: frame, to: location) { return }
            }
            throw PaneNotificationSpoolWriteError(reason: .spoolFileRepeatedlyReplaced)
        #else
            throw PaneNotificationSpoolWriteError(reason: .notificationFileUnavailable)
        #endif
    }

    #if canImport(Darwin)
        /// What one locked append attempt settled.
        private enum LockedAppendOutcome {
            case appended
            case spoolFileReplaced
        }

        /// The drain holds this same lock across a whole file rewrite, so the
        /// wait here can be as long as a drain takes.
        private func appendUnderExclusiveLock(
            frame: Data,
            to location: PaneNotificationSpoolLocation
        ) throws -> LockedAppendOutcome {
            let path = location.notificationFileURL.path
            let fileExistedBeforeAppend = FileManager.default.fileExists(atPath: path)
            let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
            guard descriptor >= 0 else {
                throw PaneNotificationSpoolWriteError(reason: .notificationFileUnavailable, errnoCode: errno)
            }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX) == 0 else {
                throw PaneNotificationSpoolWriteError(reason: .exclusiveLockUnavailable, errnoCode: errno)
            }
            defer { flock(descriptor, LOCK_UN) }
            guard try lockedDescriptorStillAnswersToPath(descriptor, path: path) else {
                return .spoolFileReplaced
            }
            _ = fchmod(descriptor, 0o600)
            try appendAllBytes(frame, to: descriptor)
            guard fsync(descriptor) == 0 else {
                throw PaneNotificationSpoolWriteError(reason: .synchronizeFailed, errnoCode: errno)
            }
            if !fileExistedBeforeAppend {
                try synchronizeDirectoryEntry(location.spoolDirectory)
            }
            return .appended
        }

        /// `flock` holds an open file description, not a name. A drain that
        /// renames its replacement over the path while this writer was waiting
        /// leaves the locked descriptor addressing an inode with no directory
        /// entry: the append there would succeed, `fsync` would succeed, and no
        /// drain would ever read the line. Comparing the locked inode against
        /// the one the path now names is what keeps the append somewhere the
        /// next drain looks.
        private func lockedDescriptorStillAnswersToPath(_ descriptor: Int32, path: String) throws -> Bool {
            var lockedStatus = stat()
            guard fstat(descriptor, &lockedStatus) == 0 else {
                throw PaneNotificationSpoolWriteError(reason: .notificationFileUnavailable, errnoCode: errno)
            }
            var pathStatus = stat()
            // An absent path is the same answer as a replaced one: reopening
            // creates the file this writer's line belongs in.
            guard stat(path, &pathStatus) == 0 else { return false }
            return lockedStatus.st_ino == pathStatus.st_ino && lockedStatus.st_dev == pathStatus.st_dev
        }

        private func prepareSpoolDirectory(_ directory: URL) throws {
            guard !FileManager.default.fileExists(atPath: directory.path) else { return }
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw PaneNotificationSpoolWriteError(reason: .spoolDirectoryUnavailable, errnoCode: errno)
            }
        }

        /// Syncing the file does not make its own directory entry durable, so a
        /// crash right after the first-ever append to a pane could lose the file
        /// the queued reply promised.
        private func synchronizeDirectoryEntry(_ directory: URL) throws {
            let descriptor = open(directory.path, O_RDONLY)
            guard descriptor >= 0 else {
                throw PaneNotificationSpoolWriteError(reason: .synchronizeFailed, errnoCode: errno)
            }
            defer { close(descriptor) }
            guard fsync(descriptor) == 0 else {
                throw PaneNotificationSpoolWriteError(reason: .synchronizeFailed, errnoCode: errno)
            }
        }

        /// `write(2)` may satisfy only part of the frame; a partial line would
        /// corrupt every later line in the file.
        private func appendAllBytes(_ frame: Data, to descriptor: Int32) throws {
            var offset = frame.startIndex
            while offset < frame.endIndex {
                let written = frame[offset...].withUnsafeBytes { buffer in
                    write(descriptor, buffer.baseAddress, buffer.count)
                }
                if written < 0 {
                    if errno == EINTR { continue }
                    throw PaneNotificationSpoolWriteError(reason: .appendFailed, errnoCode: errno)
                }
                guard written > 0 else {
                    throw PaneNotificationSpoolWriteError(reason: .appendFailed, errnoCode: errno)
                }
                offset = frame.index(offset, offsetBy: written)
            }
        }
    #endif
}

/// The one route from an unreachable app to the spool. Anything that is not an
/// eligible model notification keeps the caller's ordinary failure.
package struct PaneNotificationOfflineHandler: Sendable {
    private let writer = PaneNotificationSpoolWriter()
    private let location: PaneNotificationSpoolLocation?
    private let maximumLineBytes: Int

    package init(environment: [String: String], maximumLineBytes: Int = 1_048_576) {
        location = PaneNotificationSpoolLocation(environment: environment)
        self.maximumLineBytes = maximumLineBytes
    }

    package init(location: PaneNotificationSpoolLocation?, maximumLineBytes: Int = 1_048_576) {
        self.location = location
        self.maximumLineBytes = maximumLineBytes
    }

    /// `requestLine` is evaluated only once the notification is known eligible,
    /// so an ineligible call never encodes a wire frame.
    package func handleUnreachableApp(
        invocation: IPCDescriptorInvocation,
        requestLine: () throws -> String
    ) throws -> PaneNotificationOfflineOutcome {
        let outcome = writer.offlineOutcome(for: invocation)
        guard case .queued = outcome else { return outcome }
        guard let location else { return .notQueued }
        let line: String
        do {
            line = try requestLine()
        } catch {
            throw PaneNotificationSpoolWriteError(reason: .lineEncodingFailed)
        }
        try writer.append(requestLine: line, to: location, maximumLineBytes: maximumLineBytes)
        return outcome
    }
}
