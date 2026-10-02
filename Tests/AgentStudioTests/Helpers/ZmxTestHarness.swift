import AgentStudioTestHarness
import Darwin
import Foundation

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

/// Isolated zmx environment for integration tests.
/// Each test run uses a unique ZMX_DIR (temp directory) to prevent cross-test interference.
final class ZmxTestHarness: @unchecked Sendable {
    struct CleanupOutcome: Sendable {
        let attemptedSessionNames: [String]
        let remainingSessionNames: [String]
        let diagnostics: String
        let succeeded: Bool
    }

    struct CleanupError: Error, LocalizedError {
        let outcome: CleanupOutcome

        var errorDescription: String? { outcome.diagnostics }
    }

    /// Thrown by `waitUntilSessionSettled` when a freshly spawned session
    /// never reaches a state the production discovery mechanism can
    /// observe -- distinct from `ZmxSessionControlFailure`, whose cases all
    /// assume a session that exists to be inspected.
    enum SessionSettlementError: Error, LocalizedError {
        case socketNeverAppeared(sessionId: String)
        case terminalLeaderExitedBeforeSetsid(terminalPID: Int32)
        /// R1 Stage 1 fix (2026-09-30): `ZmxSessionControl.observeForDiscovery`'s
        /// `.terminalLeaderGone` -- the terminal leader is positively
        /// confirmed dead (`proc_pidinfo` reports `ESRCH`), not merely
        /// unverifiable, so there is nothing to retry: a dead leader stays
        /// dead.
        case terminalLeaderConfirmedGone
        /// F7 residual (advisor review round 2, Lead 2026-10-02):
        /// `waitForSessionSocket`'s own `open(2)` on `zmxDir` failing leaves
        /// no vnode to register a real watch against at all -- there is no
        /// event source to wait on, so the honest behavior is to fail
        /// immediately with the real cause, not poll a deadline hoping the
        /// directory becomes openable. Carries the exact `errno` and path
        /// so a real failure here is diagnosable, not a silent timeout.
        case sessionDirectoryUnwatchable(path: String, errno: Int32)

        var errorDescription: String? {
            switch self {
            case .socketNeverAppeared(let sessionId):
                return "zmx session socket for \(sessionId) never appeared while waiting for settlement"
            case .terminalLeaderExitedBeforeSetsid(let terminalPID):
                return "terminal leader pid \(terminalPID) exited before completing setsid"
            case .terminalLeaderConfirmedGone:
                return "terminal leader was positively confirmed dead while waiting for settlement"
            case .sessionDirectoryUnwatchable(let path, let errno):
                return "open(2) on zmx session directory \(path) failed with errno \(errno); no vnode source to watch"
            }
        }
    }

    private struct SpawnedProcess {
        let process: Process
        let processID: pid_t
    }

    let zmxDir: String
    let zmxPath: String?
    /// R1 gate (Lead 2026-10-01): a scratch `HOME`/`ZDOTDIR` for every spawned
    /// zmx/shell process, created here and removed alongside `zmxDir` in
    /// `cleanup()`. Keeps the cold-restore script's `exec <loginShell> -i -l`
    /// from sourcing the owner's real `.bash_profile`/`.profile`/`.zshrc`.
    let scratchHomeDirectory: String
    private let executor: any ProcessExecutor
    private var spawnedProcesses: [SpawnedProcess] = []
    private let clock = ContinuousClock()

    init() async {
        // UUIDv7's prefix is timestamp data shared by nearby creations. Use its random
        // tail so independent harnesses cannot list/kill each other's session roots.
        let shortId = UUIDv7.generate().uuidString.suffix(12).lowercased()
        // Use /tmp directly (not NSTemporaryDirectory) to keep socket paths under
        // the Darwin 103-byte usable Unix domain socket payload limit. Main
        // /tmp/zt-<12chars>/ leaves ample room for the app's generated session IDs.
        self.zmxDir = "/tmp/zt-\(shortId)"
        self.scratchHomeDirectory = "/tmp/zt-\(shortId)-home"
        // R2-5 gate finding (Lead 2026-10-02): `waitForSessionSocket` throws
        // `sessionDirectoryUnwatchable` instead of polling on an open(2)
        // failure now (ff3424fc9) -- but the first caller through it, right
        // after `spawnZmxSession`/`spawnColdRestoreSession`'s `process.run()`
        // returns, can race the daemon's own startup before it ever creates
        // this directory itself. Creating it here, at harness construction,
        // before any zmx process is ever spawned, removes that race
        // entirely rather than working around it with a poll or a deadline.
        // Confirmed safe against zmx's own startup: `Cfg.mkdir`'s
        // `mkdirAll` (vendor/zmx/src/cfg.zig:88-101) treats
        // `error.PathAlreadyExists` as a no-op for exactly this directory
        // (`ZMX_DIR`, zmx's own `socket_dir`) -- a daemon spawned against an
        // already-existing directory is not a new or different code path.
        try? FileManager.default.createDirectory(
            atPath: zmxDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try? FileManager.default.createDirectory(
            atPath: scratchHomeDirectory, withIntermediateDirectories: true)
        // zmx kill and list run to exit with no per-call time limit: a slow runner must not turn a
        // correct call into a timeout and a retry. A wedged zmx is caught by the lane's hang bound.
        self.executor = RunToExitProcessExecutor()

        // Resolve zmx binary: check vendored build first, then system PATH
        // 1. Vendored binary (built by scripts/build-zmx.sh or zig build)
        let vendoredPath = Self.findVendoredZmx()
        if let vendored = vendoredPath {
            self.zmxPath = vendored
        } else if let found = ["/opt/homebrew/bin/zmx", "/usr/local/bin/zmx"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        {
            self.zmxPath = found
        } else {
            // 2. Fallback: check PATH via which
            self.zmxPath = try? await withoutBlockingCooperativePool {
                let outputDirectory = FileManager.default.temporaryDirectory
                    .appending(path: "zmx-path-resolution-\(UUIDv7.generate().uuidString)")
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: outputDirectory) }
                let outputURL = outputDirectory.appending(path: "stdout.log")
                FileManager.default.createFile(atPath: outputURL.path, contents: nil)
                let outputHandle = try FileHandle(forWritingTo: outputURL)
                defer { try? outputHandle.close() }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
                process.arguments = ["zmx"]
                process.standardOutput = outputHandle
                process.standardError = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                try outputHandle.close()
                guard process.terminationStatus == 0 else { return nil }
                let path = try String(contentsOf: outputURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return path.isEmpty ? nil : path
            }
        }
    }

    init(zmxDir: String, zmxPath: String?, executor: any ProcessExecutor) {
        self.zmxDir = zmxDir
        self.zmxPath = zmxPath
        self.scratchHomeDirectory = "\(zmxDir)-home"
        try? FileManager.default.createDirectory(
            atPath: scratchHomeDirectory, withIntermediateDirectories: true)
        self.executor = executor
    }

    /// A hermetic child environment for every zmx/shell process this harness
    /// spawns, built from an explicit allowlist instead of inheriting the
    /// parent's full environment.
    ///
    /// R1 gate (Lead 2026-10-01): the gate's own test run can itself be
    /// running inside a real AgentStudio pane -- confirmed against real
    /// evidence captured from a hung zmx-e2e run (a real `ZMX_SESSION`, the
    /// owner's real `ZMX_DIR=~/.agentstudio/z`, `GHOSTTY_SURFACE_ID`,
    /// `TERM_PROGRAM=ghostty`, `__CFBundleIdentifier=com.agentstudio.app` all
    /// present in that pane's own environment). The previous shape --
    /// `ProcessInfo.processInfo.environment` plus overriding just `ZMX_DIR`,
    /// `ZMX_SESSION` and `ZMX_SESSION_PREFIX` -- let every other ambient
    /// marker reach a spawned `zmx attach`'s login shell unfiltered. zmx's
    /// own production contract (`ZmxBackend.buildAttachCommand`'s doc
    /// comment: "ZMX_DIR must be provided via process environment (Ghostty
    /// surface env vars)") means a shell that still carries those markers
    /// can end up correlated with the owner's real pane instead of this
    /// test's disposable session -- the process tree evidence for the hang
    /// this fixes was exactly that: a nested `zmx attach` sitting idle.
    ///
    /// `ZMX_SESSION` and `ZMX_SESSION_PREFIX` are never added at all, not
    /// set to empty strings: a variable that is merely present-but-empty can
    /// still read as "a session is in scope" to code that only checks
    /// existence rather than non-emptiness.
    ///
    /// `PATH` is copied from the parent but with every entry that lives
    /// inside an application bundle filtered out: `/Applications/AgentStudio
    /// .app/Contents/MacOS` on `PATH` means a script invoking `agentstudio`
    /// resolves to this GUI app's own binary on case-insensitive APFS, not a
    /// CLI tool of a similar name -- a known hazard independent of this fix.
    ///
    /// `HOME` and `ZDOTDIR` are set to `scratchHomeDirectory`, never copied
    /// from the parent: every zmx-e2e test's `folderCandidates` is `/tmp`
    /// and every `loginShell` is `/bin/bash` (confirmed by reading every
    /// call site), so nothing in this suite depends on the real `HOME`, and
    /// the cold-restore script's `exec <loginShell> -i -l` would otherwise
    /// source the owner's real `.bash_profile`/`.profile`/`.zshrc` inside a
    /// test. A future test that genuinely needs the real `HOME` must set it
    /// explicitly in its own plan/command rather than rely on this
    /// environment.
    ///
    /// `parentEnvironment` defaults to the real ambient environment at every
    /// call site; a test supplies a synthetic one to prove this allowlist in
    /// isolation without needing a real pane's environment to reproduce it.
    static func hermeticChildEnvironment(
        zmxDir: String,
        scratchHomeDirectory: String,
        parentEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment: [String: String] = [:]
        for allowlistedKey in ["USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL"] {
            if let value = parentEnvironment[allowlistedKey] {
                environment[allowlistedKey] = value
            }
        }
        environment["HOME"] = scratchHomeDirectory
        environment["ZDOTDIR"] = scratchHomeDirectory
        environment["TERM"] = "xterm-256color"
        if let inheritedPath = parentEnvironment["PATH"] {
            environment["PATH"] =
                inheritedPath
                .split(separator: ":", omittingEmptySubsequences: false)
                .filter { pathEntry in
                    let lowercasedEntry = pathEntry.lowercased()
                    return !lowercasedEntry.contains(".app/") && !lowercasedEntry.hasSuffix(".app")
                }
                .joined(separator: ":")
        }
        environment["ZMX_DIR"] = zmxDir
        return environment
    }

    /// Create a ZmxBackend configured with the test-isolated ZMX_DIR.
    func createBackend() -> ZmxBackend? {
        guard let zmxPath else { return nil }
        return ZmxBackend(executor: executor, zmxPath: zmxPath, zmxDir: zmxDir)
    }

    /// Create a ZmxBackend with a custom executor (for mixed mock/real testing).
    func createBackend(executor: ProcessExecutor) -> ZmxBackend? {
        guard let zmxPath else { return nil }
        return ZmxBackend(executor: executor, zmxPath: zmxPath, zmxDir: zmxDir)
    }

    /// Clean up all sessions in the test ZMX_DIR and remove the temp directory.
    func cleanup() async -> CleanupOutcome {
        let outcome = await cleanupSessionInventory()
        await terminateSpawnedProcesses()
        if outcome.succeeded {
            try? FileManager.default.removeItem(atPath: zmxDir)
            try? FileManager.default.removeItem(atPath: scratchHomeDirectory)
        }
        return outcome
    }

    private func cleanupSessionInventory() async -> CleanupOutcome {
        guard let zmxPath else {
            return CleanupOutcome(
                attemptedSessionNames: [],
                remainingSessionNames: [],
                diagnostics: "zmx cleanup could not resolve the zmx executable; retained \(zmxDir)",
                succeeded: false
            )
        }

        var attemptedSessionNames: [String] = []
        var diagnostics: [String] = []
        do {
            let initialInventory = try await listSessions(zmxPath: zmxPath)
            guard initialInventory.result.succeeded else {
                return cleanupFailure(
                    attemptedSessionNames: [],
                    remainingSessionNames: [],
                    diagnostics: "zmx list failed: \(initialInventory.result.stderr)"
                )
            }

            attemptedSessionNames = initialInventory.sessionNames
            for sessionName in attemptedSessionNames {
                do {
                    let killResult = try await executor.execute(
                        command: zmxPath,
                        args: ["kill", sessionName],
                        cwd: nil,
                        environment: ["ZMX_DIR": zmxDir]
                    )
                    if !killResult.succeeded {
                        diagnostics.append("zmx kill failed for \(sessionName): \(killResult.stderr)")
                    }
                } catch {
                    diagnostics.append("zmx kill failed for \(sessionName): \(error)")
                }
            }

            let deadline = clock.now.advanced(by: .seconds(5))
            var remainingSessionNames = attemptedSessionNames
            repeat {
                let verification = try await listSessions(zmxPath: zmxPath)
                guard verification.result.succeeded else {
                    diagnostics.append("zmx verification list failed: \(verification.result.stderr)")
                    return cleanupFailure(
                        attemptedSessionNames: attemptedSessionNames,
                        remainingSessionNames: remainingSessionNames,
                        diagnostics: diagnostics.joined(separator: "\n")
                    )
                }
                remainingSessionNames = verification.sessionNames
                if remainingSessionNames.isEmpty {
                    if diagnostics.isEmpty {
                        return CleanupOutcome(
                            attemptedSessionNames: attemptedSessionNames,
                            remainingSessionNames: [],
                            diagnostics: "zmx cleanup verified zero sessions",
                            succeeded: true
                        )
                    }
                    return cleanupFailure(
                        attemptedSessionNames: attemptedSessionNames,
                        remainingSessionNames: [],
                        diagnostics: diagnostics.joined(separator: "\n")
                    )
                }
                try? await clock.sleep(for: .milliseconds(50))
            } while clock.now < deadline

            diagnostics.append("zmx cleanup timed out with sessions: \(remainingSessionNames.joined(separator: ", "))")
            return cleanupFailure(
                attemptedSessionNames: attemptedSessionNames,
                remainingSessionNames: remainingSessionNames,
                diagnostics: diagnostics.joined(separator: "\n")
            )
        } catch {
            return cleanupFailure(
                attemptedSessionNames: attemptedSessionNames,
                remainingSessionNames: attemptedSessionNames,
                diagnostics: "zmx cleanup command failed: \(error)"
            )
        }
    }

    private func listSessions(zmxPath: String) async throws -> (result: ProcessResult, sessionNames: [String]) {
        let result = try await executor.execute(
            command: zmxPath,
            args: ["list"],
            cwd: nil,
            environment: ["ZMX_DIR": zmxDir]
        )
        let sessionNames = result.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { Self.extractSessionName(from: String($0)) }
        return (result, sessionNames)
    }

    private func cleanupFailure(
        attemptedSessionNames: [String],
        remainingSessionNames: [String],
        diagnostics: String
    ) -> CleanupOutcome {
        CleanupOutcome(
            attemptedSessionNames: attemptedSessionNames,
            remainingSessionNames: remainingSessionNames,
            diagnostics: "\(diagnostics)\nretained zmx root: \(zmxDir)",
            succeeded: false
        )
    }

    func sessionSocketPath(for sessionId: String) -> String {
        URL(fileURLWithPath: zmxDir).appendingPathComponent(sessionId).path
    }

    /// F7 residual (advisor review round 2, Lead 2026-10-02): `open(2)`
    /// failing on `zmxDir` used to fall back to a deadline poll -- the
    /// owner's rule bans deadline polling in tests outright, and having no
    /// event source available is not an exemption. There is nothing to
    /// register a real watch against in that case, so the honest test
    /// behavior is to fail immediately with the real cause
    /// (`SessionSettlementError.sessionDirectoryUnwatchable`), not poll
    /// hoping the directory becomes openable. No deadline/timeout
    /// parameter remains on this function at all.
    func waitForSessionSocket(
        sessionId: String,
        exists expectedExists: Bool
    ) async throws -> Bool {
        let sessionSocketPath = sessionSocketPath(for: sessionId)
        if FileManager.default.fileExists(atPath: sessionSocketPath) == expectedExists {
            return true
        }

        let directoryFileDescriptor = open(zmxDir, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else {
            throw SessionSettlementError.sessionDirectoryUnwatchable(path: zmxDir, errno: errno)
        }
        // R2-4 item 2 (review round 2, Lead 2026-10-01): ownership of this
        // descriptor passes to `awaitSessionSocketEvent`, which now closes
        // it from its own dispatch source's cancel handler -- the SDK's
        // documented safe boundary (source.h:449), matching A4's own
        // `closeWatchedDirectory`-from-cancel-handler shape in production.
        // A bare `defer` here would close it the instant that call
        // returns, which is not the same moment: `dispatch_source_cancel`
        // only requests cancellation (source.h:512), so this scope's own
        // close could race the source's still-in-flight teardown.
        return await awaitSessionSocketEvent(
            fileDescriptor: directoryFileDescriptor,
            sessionSocketPath: sessionSocketPath,
            exists: expectedExists
        )
    }

    /// Spawn a zmx attach command against a real zmx daemon and block until
    /// its terminal leader is past the `setsid` race window (Amended
    /// 2026-09-30: the identical race `ColdStartObserver.beginSetsidWatch`
    /// fixes for discovery was also flaking a direct `observe(path:bootID:)`
    /// caller inspecting a session spawned here before its leader had
    /// settled -- see `waitUntilSessionSettled`). Every caller that needs a
    /// real, inspectable session gets one; no sleeps, no retry-until loop.
    ///
    /// The returned process must be awaited by callers through `cleanup()`.
    func spawnZmxSession(
        zmxPath: String,
        sessionId: String,
        commandArgs: [String]
    ) async throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: zmxPath)
        process.arguments = ["attach", sessionId] + commandArgs
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = Pipe()
        process.environment = Self.hermeticChildEnvironment(zmxDir: zmxDir, scratchHomeDirectory: scratchHomeDirectory)
        try process.run()

        let processID = process.processIdentifier
        spawnedProcesses.append(
            SpawnedProcess(
                process: process,
                processID: processID
            ))

        try await waitUntilSessionSettled(sessionId: sessionId)
        return process
    }

    /// Spawn a real cold-restore session exactly as production builds it
    /// (`ZmxBackend.buildColdRestoreCommand`, in turn
    /// `TerminalRestoreRuntime.startupCommand(for:kind:.cold)`) -- S3's
    /// zmx-e2e proof exercises the real command string, not a hand-rolled
    /// approximation. `buildColdRestoreCommand`'s result is a single,
    /// already shell-quoted command line starting with the zmx executable
    /// itself, so it runs through `/bin/sh -c` exactly as a user pasting it
    /// would.
    ///
    /// Blocks until the session's terminal leader is past the `setsid` race
    /// window, same as `spawnZmxSession`. A test that deliberately needs a
    /// session before that point (or one that never reaches zmx at all, such
    /// as a bogus `zmxExecutable`) spawns through
    /// `spawnColdRestoreSessionWithoutWaitingForSettlement` instead.
    ///
    /// The returned process must be awaited by callers through `cleanup()`.
    func spawnColdRestoreSession(plan: TerminalColdRestorePlan) async throws -> Process {
        let process = try spawnColdRestoreSessionWithoutWaitingForSettlement(plan: plan)
        try await waitUntilSessionSettled(sessionId: plan.sessionID.rawValue)
        return process
    }

    /// The half-created counterpart to `spawnColdRestoreSession`: launches
    /// the attach command and returns immediately, with no wait for the
    /// session to become discoverable or its leader to complete `setsid`.
    /// For a test that deliberately exercises a session before, or without
    /// ever reaching, that point -- for example a bogus `zmxExecutable`
    /// whose attach client exits before any socket exists.
    ///
    /// The returned process must be awaited by callers through `cleanup()`.
    func spawnColdRestoreSessionWithoutWaitingForSettlement(plan: TerminalColdRestorePlan) throws -> Process {
        try spawnShellCommandWithoutWaitingForSettlement(ZmxBackend.buildColdRestoreCommand(plan))
    }

    /// The general form of `spawnColdRestoreSessionWithoutWaitingForSettlement`
    /// for a caller that already has its own full command line -- such as
    /// `TerminalRestoreRuntime.startupCommand(for:kind:)`'s own returned
    /// string -- rather than a `TerminalColdRestorePlan` to build one from
    /// (S4b "option A" zmx-e2e proof: the production entry point itself,
    /// not just `ZmxBackend.buildColdRestoreCommand`, reaches real zmx).
    /// No settlement wait, for the same reason as the plan-based sibling:
    /// a caller reconnecting to an already-alive leader has no fresh
    /// incarnation to wait for, and a caller expecting recreation instead
    /// waits on its own observable proof (a socket, an identity, session
    /// history) after this returns.
    ///
    /// The returned process must be awaited by callers through `cleanup()`.
    func spawnShellCommandWithoutWaitingForSettlement(_ commandLine: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", commandLine]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = Pipe()
        process.environment = Self.hermeticChildEnvironment(zmxDir: zmxDir, scratchHomeDirectory: scratchHomeDirectory)
        try process.run()

        let processID = process.processIdentifier
        spawnedProcesses.append(
            SpawnedProcess(
                process: process,
                processID: processID
            ))

        return process
    }

    /// F7 (review round 1): the general form of
    /// `spawnShellCommandWithoutWaitingForSettlement`, for R1's option-A
    /// zmx-e2e cases that must read the attach client's own real output
    /// (the restore notice a fallback script prints) instead of polling
    /// `zmx history`. Confirmed against zmx's own source at the pinned
    /// commit: `history` reads no file -- it answers over the session's
    /// control socket from the daemon's in-memory terminal state
    /// (main.zig:1377-1437 `fetchHistory`, loop.zig:1129-1146
    /// `handleHistory`) -- so there is no filesystem event to watch for it,
    /// and repolling it is the only alternative to reading real output.
    ///
    /// A separate variant rather than a parameter on the shared helper, so
    /// every inherited caller of `spawnShellCommandWithoutWaitingForSettlement`
    /// keeps its stdout nulled exactly as before.
    ///
    /// The returned process must be awaited by callers through `cleanup()`.
    func spawnShellCommandCapturingOutput(_ commandLine: String) throws -> (process: Process, standardOutput: Pipe) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", commandLine]
        let standardOutputPipe = Pipe()
        process.standardOutput = standardOutputPipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = Pipe()
        process.environment = Self.hermeticChildEnvironment(zmxDir: zmxDir, scratchHomeDirectory: scratchHomeDirectory)
        try process.run()

        let processID = process.processIdentifier
        spawnedProcesses.append(
            SpawnedProcess(
                process: process,
                processID: processID
            ))

        return (process, standardOutputPipe)
    }

    func sessionHistory(sessionId: String) async throws -> String {
        guard let zmxPath else { return "" }
        let result = try await executor.execute(
            command: zmxPath,
            args: ["history", sessionId],
            cwd: nil,
            environment: ["ZMX_DIR": zmxDir]
        )
        return result.stdout
    }

    /// Blocks until a freshly spawned session's terminal leader has
    /// completed `setsid()`, using the exact production discovery mechanism
    /// (`ZmxSessionControl.observeForDiscovery`, backed off on a refused
    /// connect, and an `EVFILT_PROC NOTE_EXEC` watch when setsid hasn't
    /// landed yet) rather than a sleep or a retry-until poll loop --
    /// mirroring `ColdStartObserver.attemptDiscoveryConnect` and
    /// `beginSetsidWatch`. `spawnZmxSession` and `spawnColdRestoreSession`
    /// call this before returning, so every zmx-e2e test that spawns
    /// through them starts from a session whose leader is already past the
    /// setsid race window.
    @discardableResult
    private func waitUntilSessionSettled(sessionId: String) async throws -> ZmxSessionIdentity {
        guard try await waitForSessionSocket(sessionId: sessionId, exists: true) else {
            throw SessionSettlementError.socketNeverAppeared(sessionId: sessionId)
        }
        let socketPath = sessionSocketPath(for: sessionId)
        let bootID = try await WorkspaceUndoJournalClock.current().bootID
        return try await resolveSettledDiscovery(socketPath: socketPath, bootID: bootID, retryIndex: 0)
    }

    private func resolveSettledDiscovery(
        socketPath: String,
        bootID: String,
        retryIndex: Int
    ) async throws -> ZmxSessionIdentity {
        switch ZmxSessionControl.observeForDiscovery(path: socketPath, bootID: bootID) {
        case .identity(let identity):
            return identity
        case .pendingSetsid(let terminalPID):
            return try await resolveViaSetsidWatch(terminalPID: terminalPID, socketPath: socketPath, bootID: bootID)
        case .terminalLeaderGone:
            throw SessionSettlementError.terminalLeaderConfirmedGone
        case .failure(let failure) where Self.isTransientDuringSettlement(failure):
            // Amended 2026-09-30 against evidence, not guessed: a fresh
            // two-daemon spawn ("orphan discovery finds untracked session")
            // hit .timeout on its first full zmx-e2e run here. This wait
            // runs right after the socket first appears -- the same early,
            // racy window `waitForObservedSessionIdentity` below already
            // tolerates .unavailable/.connectionRefused/.processUnverifiable
            // /.timeout on for the identical reason ("a busy startup may not
            // answer within one bounded request"). ColdStartObserver's own
            // attemptDiscoveryConnect only retries .connectionRefused
            // because its directory-watch trigger already gives the daemon
            // more time before the first connect; this harness wait has no
            // such head start, so it matches the broader, already-proven
            // tolerance instead.
            //
            // F7 (review round 1): exhausting the backoff schedule must not
            // throw -- that would fail this wait on elapsed time alone,
            // which the production discoverer
            // (`ColdStartObserver.attemptDiscoveryConnect`) never does for
            // this same failure: exhausting its own identical schedule
            // just leaves the window "discovering," resolved only by a
            // later real fact. This harness has no later event source to
            // lean on for this specific transient case, so past the
            // schedule's own last entry it keeps retrying at that entry's
            // cadence -- bounded only by the suite's runner-owned hang
            // bound, never by a time budget of its own.
            //
            // R2-4 item 1 (review round 2, Lead 2026-10-01): `try?`
            // swallowed every throw from `clock.sleep`, cancellation
            // included -- the suite's own hang bound relies on task
            // cancellation to end an owned wait, and this loop kept
            // retrying through it regardless. `try await` instead: this
            // function is already `async throws`, so a thrown
            // `CancellationError` (or any other) now ends the retry here
            // and propagates to `waitUntilSessionSettled`'s own caller
            // exactly as every other failure case in this `switch` already
            // does, rather than retrying past it.
            let delaysMilliseconds = AppPolicies.Restore.discoveryConnectRetryDelays
            let delayIndex = min(retryIndex, delaysMilliseconds.count - 1)
            try await clock.sleep(for: .milliseconds(delaysMilliseconds[delayIndex]))
            return try await resolveSettledDiscovery(socketPath: socketPath, bootID: bootID, retryIndex: retryIndex + 1)
        case .failure(let failure):
            throw failure
        }
    }

    private static func isTransientDuringSettlement(_ failure: ZmxSessionControlFailure) -> Bool {
        switch failure {
        case .connectionRefused, .unavailable, .processUnverifiable, .timeout:
            return true
        case .invalidIdentity, .invalidSocketPath, .invalidResponse, .identityMismatch,
            .unexpectedProcessParent, .unexpectedProcessGroup, .nativeAttachmentPresent, .awaitingProcessExit:
            return false
        }
    }

    /// Register-then-check, exactly like `ColdStartObserver
    /// .beginSetsidWatch`/`checkForSetsidAndAdvance`: the leader can
    /// complete setsid and exec between the `.pendingSetsid` observation
    /// above and this registration, so the mandatory initial check must
    /// run only once kernel registration is confirmed complete, not
    /// synchronously after `resume()` returns on the caller's own Task.
    ///
    /// R2-4 item 2 (review round 2, Lead 2026-10-01): the prior shape ran
    /// that initial check synchronously right after `resume()`, which only
    /// requests registration -- the SDK's own contract (source.h:745) says
    /// the registration handler fires "once the corresponding kevent() has
    /// been registered with the system, following the initial
    /// dispatch_resume()". A transition landing in the gap between
    /// `resume()` returning and kernel registration actually completing
    /// could be missed by both: the kqueue wasn't registered yet to catch
    /// it as an edge, and the synchronous check had already read "still
    /// pending." Setting `setRegistrationHandler` before `resume()`, and
    /// running the same check from it, closes that gap -- the same one F1
    /// fixed in production. Both the event handler and the registration
    /// handler now run on this source's own GCD queue and may call
    /// `arriveBlocking` directly; there is no longer a separate
    /// caller's-Task code path.
    private func resolveViaSetsidWatch(
        terminalPID: Int32,
        socketPath: String,
        bootID: String
    ) async throws -> ZmxSessionIdentity {
        // `HeldStep` itself already guarantees only the first arrival is
        // returned by `firstArrival()` -- a later arrival is simply
        // recorded and ignored, so the former hand-kept `SettlementGate`
        // added nothing `HeldStep` doesn't already provide.
        let step = HeldStep<Result<ZmxSessionIdentity, any Error>>(
            "zmx setsid watch settlement")
        let source = DispatchSource.makeProcessSource(
            identifier: terminalPID,
            eventMask: [.exit, .exec],
            queue: DispatchQueue.global(qos: .userInitiated)
        )

        // Pure: nil means "not settled yet, stays armed." Shared by the
        // registration handler's mandatory initial check and the event
        // handler's later re-checks -- both now run on this source's own
        // GCD queue, never on the caller's Task.
        func outcome(exitFired: Bool) -> Result<ZmxSessionIdentity, any Error>? {
            if exitFired {
                return .failure(SessionSettlementError.terminalLeaderExitedBeforeSetsid(terminalPID: terminalPID))
            }
            switch ZmxSessionControl.observeForDiscovery(path: socketPath, bootID: bootID) {
            case .identity(let identity):
                return .success(identity)
            case .pendingSetsid:
                return nil  // not settled yet; the watch stays armed for the next event
            case .terminalLeaderGone:
                return .failure(SessionSettlementError.terminalLeaderConfirmedGone)
            case .failure(let failure):
                return .failure(failure)
            }
        }

        // One shared check, called from both the event handler and the
        // registration handler -- mirroring `ColdStartObserver
        // .beginSetsidWatch`'s own `checkForSetsidAndAdvance` shape.
        // Idempotent: a settled source is already cancelled, so a harmless
        // re-entry from the other callback finds nothing left to check
        // (`outcome` would be called again, but `step.arriveBlocking` after
        // the first `firstArrival()` only records and is ignored).
        func checkAndSettleIfReady(exitFired: Bool) {
            guard let result = outcome(exitFired: exitFired) else { return }
            source.cancel()
            // A raw GCD callback on .global(), not inside a Swift Task.
            try? step.arriveBlocking(result)
        }

        source.setEventHandler {
            checkAndSettleIfReady(exitFired: source.data.contains(.exit))
        }
        source.setCancelHandler {}
        // The mandatory initial check: `exitFired: false` mirrors the event
        // handler's own shape for this call -- this firing carries no real
        // `NOTE_EXIT`, so an already-dead leader is still caught by
        // `ZmxSessionControl.observeForDiscovery`'s own `.terminalLeaderGone`
        // case inside `outcome`, not assumed from this call alone.
        source.setRegistrationHandler {
            checkAndSettleIfReady(exitFired: false)
        }
        source.resume()

        let settled = try await step.firstArrival()
        step.release()
        return try settled.get()
    }

    /// F7 (review round 1): no more a timed race. A real-time `clock.sleep`
    /// racing the real vnode event made this return `false` ("never
    /// appeared") whenever the daemon was merely slow, not actually broken
    /// -- "wrapping a timeout in HeldStep does not change what determines
    /// its verdict." Register-then-check against the real event alone now;
    /// a socket that genuinely never appears is caught by the suite's own
    /// runner-owned hang bound, which names this step
    /// ("session socket event") as what was awaited. A caller that needs a
    /// true negative result (not just a hang) must race this against a
    /// correlated real fact of its own -- the zmx process it expected to
    /// create the socket exiting -- not against time.
    ///
    /// R2-4 item 2 (review round 2, Lead 2026-10-01): the prior shape ran
    /// its "register-then-check" synchronously on the caller's own Task
    /// right after `resume()`, which only requests kernel registration
    /// (source.h:745) -- a transition landing in the gap before that
    /// registration actually completes could be missed by both the
    /// not-yet-armed kqueue and the already-run synchronous check. Moving
    /// the mandatory initial check into `setRegistrationHandler` closes
    /// that gap, mirroring `resolveViaSetsidWatch`'s identical fix above.
    /// The cancel handler now also owns closing `fileDescriptor` -- the
    /// caller (`waitForSessionSocket`) no longer does, for the same A4
    /// reasoning: only the cancel handler is the SDK's documented
    /// safe-to-close point (source.h:449).
    private func awaitSessionSocketEvent(
        fileDescriptor: Int32,
        sessionSocketPath: String,
        exists expectedExists: Bool
    ) async -> Bool {
        let step = HeldStep<Bool>("session socket event")
        let eventSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .userInitiated)
        )

        // Shared by the registration handler's mandatory initial check and
        // the event handler's later re-checks -- both run on this source's
        // own GCD queue, never on the caller's Task, so both may call
        // `arriveBlocking` directly. Idempotent: a settled source is
        // already cancelled, so a harmless re-entry from the other
        // callback finds nothing new to do.
        func checkAndSettleIfReady() {
            guard FileManager.default.fileExists(atPath: sessionSocketPath) == expectedExists else { return }
            eventSource.cancel()
            // A raw GCD callback on .global(), not inside a Swift Task.
            try? step.arriveBlocking(true)
        }

        eventSource.setEventHandler {
            checkAndSettleIfReady()
        }
        // A4-shaped: closes the descriptor this source owns, exactly once,
        // only once cancellation has actually completed.
        eventSource.setCancelHandler {
            close(fileDescriptor)
        }
        // The mandatory initial check, run once kernel registration is
        // confirmed complete -- not synchronously after `resume()` returns.
        eventSource.setRegistrationHandler {
            checkAndSettleIfReady()
        }
        eventSource.resume()

        let result = (try? await step.firstArrival()) ?? false
        step.release()
        // Safety net, not the primary path: if `firstArrival()` returned
        // through external cancellation rather than a matched check above,
        // the source may still be live -- cancelling here is a no-op when
        // already cancelled, and still routes the descriptor's close
        // through the cancel handler either way.
        eventSource.cancel()
        return result
    }

    /// Walk up from the test binary to find vendor/zmx/zig-out/bin/zmx.
    private static func findVendoredZmx() -> String? {
        let projectRoot = TestPathResolver.projectRoot(from: #filePath)
        let candidate = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent("vendor/zmx/zig-out/bin/zmx")
            .path
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    static func extractSessionName(from line: String) -> String? {
        ZmxBackend.extractSessionName(from: line)
    }

    private func terminateSpawnedProcesses() async {
        let parentProcessGroup = getpid() > 0 ? processGroupID(for: getpid()) : nil

        for entry in spawnedProcesses {
            if entry.processID <= 0 {
                continue
            }

            if let processGroup = processGroupID(for: entry.processID),
                let parentGroup = parentProcessGroup,
                processGroup > 0,
                processGroup != parentGroup
            {
                terminateProcess(-processGroup, signal: SIGKILL)
            } else {
                let descendants = await collectDescendantProcessIDs(
                    of: entry.processID
                )
                for pid in ([entry.processID] + descendants).reversed() {
                    if pid > 0 {
                        terminateProcess(pid, signal: SIGKILL)
                    }
                }
            }

            if entry.process.isRunning {
                entry.process.terminate()
            }
        }

        spawnedProcesses.removeAll()
    }

    private func processGroupID(for pid: pid_t) -> pid_t? {
        let pgid = getpgid(pid)
        return pgid > 0 ? pgid : nil
    }

    private func collectDescendantProcessIDs(of pid: pid_t) async -> [pid_t] {
        var descendants: [pid_t] = []
        var queue: [pid_t] = [pid]

        while let current = queue.popLast() {
            let children = await childProcessIDs(of: current)
            descendants.append(contentsOf: children)
            queue.append(contentsOf: children)
        }

        return descendants
    }

    private func childProcessIDs(of parentPID: pid_t) async -> [pid_t] {
        let pgrepPath = "/usr/bin/pgrep"
        guard FileManager.default.isExecutableFile(atPath: pgrepPath) else {
            logError("pgrep is not executable at \(pgrepPath); cannot enumerate child processes")
            return []
        }

        do {
            let result = try await withoutBlockingCooperativePool {
                let outputDirectory = FileManager.default.temporaryDirectory
                    .appending(path: "zmx-pgrep-\(UUIDv7.generate().uuidString)")
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: outputDirectory) }
                let stdoutURL = outputDirectory.appending(path: "stdout.log")
                let stderrURL = outputDirectory.appending(path: "stderr.log")
                FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
                FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
                let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
                let stderrHandle = try FileHandle(forWritingTo: stderrURL)
                defer {
                    try? stdoutHandle.close()
                    try? stderrHandle.close()
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: pgrepPath)
                process.arguments = ["-P", "\(parentPID)"]
                process.standardOutput = stdoutHandle
                process.standardError = stderrHandle
                try process.run()
                process.waitUntilExit()
                try stdoutHandle.close()
                try stderrHandle.close()
                return (
                    process.terminationStatus,
                    try Data(contentsOf: stdoutURL),
                    try Data(contentsOf: stderrURL)
                )
            }

            switch result.0 {
            case 0:
                guard let output = String(data: result.1, encoding: .utf8) else {
                    logError("pgrep produced non-UTF8 output for parent PID \(parentPID)")
                    return []
                }
                return
                    output
                    .split(whereSeparator: \.isNewline)
                    .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .map { pid_t($0) }

            case 1:
                return []

            default:
                let stderr = String(data: result.2, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let details = stderr.map { " stderr=\($0)" } ?? ""
                logError(
                    "pgrep failed for parent PID \(parentPID) with exit status \(result.0).\(details)")
                return []
            }
        } catch {
            logError("pgrep invocation failed for parent PID \(parentPID): \(error)")
            return []
        }
    }

    private func terminateProcess(_ pid: pid_t, signal: Int32) {
        guard pid != 0 else { return }
        let result = Darwin.kill(pid, signal)
        if result == 0 { return }

        let code = errno
        let message = String(cString: strerror(code))
        if code == ESRCH {
            return
        }

        if code == EPERM {
            logError("kill permission denied for pid \(pid) with signal \(signal): \(message) (errno \(code))")
            return
        }

        logError("failed to kill pid \(pid) with signal \(signal): \(message) (errno \(code))")
    }

    private func logError(_ message: String) {
        let data = Data("[ZmxTestHarness] \(message)\n".utf8)
        if !data.isEmpty {
            FileHandle.standardError.write(data)
        }
    }

}
