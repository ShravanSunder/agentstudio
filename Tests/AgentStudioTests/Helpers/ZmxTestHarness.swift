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

        var errorDescription: String? {
            switch self {
            case .socketNeverAppeared(let sessionId):
                return "zmx session socket for \(sessionId) never appeared while waiting for settlement"
            case .terminalLeaderExitedBeforeSetsid(let terminalPID):
                return "terminal leader pid \(terminalPID) exited before completing setsid"
            case .terminalLeaderConfirmedGone:
                return "terminal leader was positively confirmed dead while waiting for settlement"
            }
        }
    }

    private struct SpawnedProcess {
        let process: Process
        let processID: pid_t
    }

    let zmxDir: String
    let zmxPath: String?
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
        self.executor = executor
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

    func waitForSessionSocket(
        sessionId: String,
        exists expectedExists: Bool,
        timeout: Duration = .seconds(10)
    ) async -> Bool {
        let sessionSocketPath = sessionSocketPath(for: sessionId)
        if FileManager.default.fileExists(atPath: sessionSocketPath) == expectedExists {
            return true
        }

        let directoryFileDescriptor = open(zmxDir, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else {
            return await fallbackWaitForSessionSocket(
                sessionId: sessionId,
                exists: expectedExists,
                timeout: timeout
            )
        }
        defer { close(directoryFileDescriptor) }
        return await awaitSessionSocketEvent(
            fileDescriptor: directoryFileDescriptor,
            sessionSocketPath: sessionSocketPath,
            exists: expectedExists,
            timeout: timeout
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
        var env = ProcessInfo.processInfo.environment
        env["ZMX_DIR"] = zmxDir
        env["ZMX_SESSION"] = ""
        env["ZMX_SESSION_PREFIX"] = ""
        process.environment = env
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
        var env = ProcessInfo.processInfo.environment
        env["ZMX_DIR"] = zmxDir
        env["ZMX_SESSION"] = ""
        env["ZMX_SESSION_PREFIX"] = ""
        process.environment = env
        try process.run()

        let processID = process.processIdentifier
        spawnedProcesses.append(
            SpawnedProcess(
                process: process,
                processID: processID
            ))

        return process
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

    func waitForSessionHistory(
        sessionId: String,
        containing expectedContent: String,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let history = try? await sessionHistory(sessionId: sessionId),
                history.contains(expectedContent)
            {
                return true
            }
            try? await clock.sleep(for: .milliseconds(50))
        }
        return false
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
        guard await waitForSessionSocket(sessionId: sessionId, exists: true) else {
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
            let delaysMilliseconds = AppPolicies.Restore.discoveryConnectRetryDelays
            guard retryIndex < delaysMilliseconds.count else {
                throw failure
            }
            try? await clock.sleep(for: .milliseconds(delaysMilliseconds[retryIndex]))
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
    /// above and this registration, so the immediate check right after
    /// `resume()` catches that already-true fact instead of missing the
    /// kqueue event and hanging. The same event handler serves later
    /// `NOTE_EXEC`/`NOTE_EXIT` events too, staying armed on a
    /// still-`.pendingSetsid` read.
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

        // Pure: nil means "not settled yet, stays armed." Shared by the GCD
        // callback and the immediate register-then-check below, since only
        // the former may call `arriveBlocking` -- the latter runs on this
        // async function's own Task and would misuse it.
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

        source.setEventHandler {
            if let result = outcome(exitFired: source.data.contains(.exit)) {
                source.cancel()
                // A raw GCD callback on .global(), not inside a Swift Task.
                try? step.arriveBlocking(result)
            }
        }
        source.setCancelHandler {}
        source.resume()

        // Register-then-check: setsid (and the exec after it) may already
        // have completed by the time this registers. An already-settled
        // result here short-circuits directly, cancelling the source
        // before any `firstArrival()` wait is even needed -- this call runs
        // on the caller's own Task, so it must not touch `arriveBlocking`.
        if let immediateResult = outcome(exitFired: false) {
            source.cancel()
            return try immediateResult.get()
        }

        let settled = try await step.firstArrival()
        step.release()
        return try settled.get()
    }

    private func awaitSessionSocketEvent(
        fileDescriptor: Int32,
        sessionSocketPath: String,
        exists expectedExists: Bool,
        timeout: Duration
    ) async -> Bool {
        // `HeldStep` already guarantees only the first arrival settles the
        // wait (the former hand-kept `CompletionGate` added nothing beyond
        // that), and its own race between an event and a timeout arrival is
        // exactly this function's shape.
        let step = HeldStep<Bool>("session socket event")
        let eventSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        eventSource.setEventHandler {
            let currentExists = FileManager.default.fileExists(atPath: sessionSocketPath)
            if currentExists == expectedExists {
                eventSource.cancel()
                // A raw GCD callback on .global(), not inside a Swift Task.
                try? step.arriveBlocking(true)
            }
        }
        eventSource.setCancelHandler {}
        eventSource.resume()

        // Register-then-check: this call runs on the caller's own Task, so
        // it must not touch `arriveBlocking` -- an already-true result
        // short-circuits directly, before ever starting the timeout task.
        if FileManager.default.fileExists(atPath: sessionSocketPath) == expectedExists {
            eventSource.cancel()
            return true
        }

        let timeoutTask = Task {
            do {
                try await self.clock.sleep(for: timeout)
            } catch {
                return
            }
            // Inside a Task, unlike the GCD callback above: the async seam.
            try? await step.arrive(false)
        }

        let result = (try? await step.firstArrival()) ?? false
        step.release()
        timeoutTask.cancel()
        eventSource.cancel()
        return result
    }

    private func fallbackWaitForSessionSocket(
        sessionId: String,
        exists expectedExists: Bool,
        timeout: Duration
    ) async -> Bool {
        let deadline = clock.now + timeout
        let sessionSocketPath = sessionSocketPath(for: sessionId)
        while clock.now < deadline {
            if FileManager.default.fileExists(atPath: sessionSocketPath) == expectedExists {
                return true
            }
            await Task.yield()
        }
        return FileManager.default.fileExists(atPath: sessionSocketPath) == expectedExists
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
