import AgentStudioCore
import AgentStudioInfrastructure
import Darwin
import Foundation

/// Ephemeral ps input. argv0 must never enter the durable observation row.
package struct ForegroundProcessSample: Sendable {
    package let incarnation: ProcessIncarnation
    package let processGroupId: Int32
    package let foregroundGroupId: Int32
    package let argv0: String
}

package struct ForegroundPsPass: Sendable {
    package let samples: [ForegroundProcessSample]
    package let complete: Bool
}

package struct DarwinTerminalForegroundProbe: TerminalForegroundProbing {
    private let sessionControl: any ZmxSessionControlling
    private let readSamples: (@Sendable () async throws -> ForegroundPsPass)?
    /// Restore R3 "probe" cost phase: forwarded to the `/bin/ps`
    /// `DefaultProcessExecutor` call below, scoped so only that call's
    /// Dispatch-side cost is measured — never the zmx socket round-trips
    /// above it, which are not part of this approved instrumentation.
    private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?

    package init(
        sessionDirectory: String, bootId: String,
        sessionControl: (any ZmxSessionControlling)? = nil,
        readSamples: (@Sendable () async throws -> ForegroundPsPass)? = nil,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) {
        self.sessionControl = sessionControl ?? ForegroundZmxSessionControl(directory: sessionDirectory, bootId: bootId)
        self.readSamples = readSamples
        self.performanceTraceRecorder = performanceTraceRecorder
    }

    @concurrent nonisolated package func probeForeground(of sessions: [ZmxSessionID]) async throws
        -> [ZmxSessionID: ForegroundSnapshot]
    {
        var identities: [ZmxSessionID: (Data, ZmxSessionIdentity)] = [:]
        for sessionId in Set(sessions) {
            try Task.checkCancellation()
            do {
                if let data = try await sessionControl.observeSessionIdentity(sessionId) {
                    identities[sessionId] = (data, try ZmxSessionIdentity.decode(data))
                }
            } catch is CancellationError { throw CancellationError() } catch { continue }
        }
        guard !identities.isEmpty else { return [:] }
        let pass: ForegroundPsPass
        if let readSamples {
            pass = try await readSamples()
        } else {
            pass = try await Self.readNativeSamples(
                leaders: identities.values.map { $0.1.terminalLeader },
                performanceTraceRecorder: performanceTraceRecorder)
        }
        var snapshots: [ZmxSessionID: ForegroundSnapshot] = [:]
        for (sessionId, captured) in identities {
            let (data, identity) = captured
            // The socket may have disappeared or been replaced during ps.
            // Only a positively unchanged session may contribute a record.
            guard let current = try? await sessionControl.observeSessionIdentity(sessionId), current == data else {
                continue
            }
            let leader = identity.terminalLeader
            let program = Self.classify(leader: leader, samples: pass.samples, complete: pass.complete)
            let agent = Self.foregroundRows(leader: leader, samples: pass.samples).first {
                Self.agentProgram(argv0: $0.argv0) == program && (program == .claudeCode || program == .codex)
            }
            snapshots[sessionId] = ForegroundSnapshot(
                sessionIdentity: data, foregroundProcess: agent?.incarnation, program: program)
        }
        return snapshots
    }

    package static func classify(
        leader: ProcessIncarnation, samples: [ForegroundProcessSample], complete: Bool
    ) -> ForegroundProgram {
        guard complete else { return .unknown }
        let foreground = foregroundRows(leader: leader, samples: samples)
        guard !foreground.isEmpty, foreground.allSatisfy({ !$0.argv0.isEmpty }) else { return .unknown }
        for sample in foreground {
            if let agent = agentProgram(argv0: sample.argv0) { return agent }
        }
        let shells = ["sh", "bash", "zsh", "fish", "dash", "ksh", "csh", "tcsh"]
        return foreground.allSatisfy { shells.contains(binaryName($0.argv0)) } ? .shell : .other
    }

    private static func foregroundRows(leader: ProcessIncarnation, samples: [ForegroundProcessSample])
        -> [ForegroundProcessSample]
    {
        guard let shell = samples.first(where: { $0.incarnation == leader }), shell.foregroundGroupId > 0 else {
            return []
        }
        return samples.filter { $0.processGroupId == shell.foregroundGroupId }
    }

    private static func binaryName(_ argv0: String) -> String {
        let basename = (argv0 as NSString).lastPathComponent
        return basename.hasPrefix("-") ? String(basename.dropFirst()) : basename
    }

    private static func agentProgram(argv0: String) -> ForegroundProgram? {
        switch binaryName(argv0) {
        case "claude": .claudeCode
        case "codex": .codex
        default: nil
        }
    }

    /// Only metadata comes from ps. argv is read solely for the requested
    /// terminal leaders' foreground groups and discarded with this pass.
    @concurrent nonisolated private static func readNativeSamples(
        leaders: [ProcessIncarnation], performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    ) async throws -> ForegroundPsPass {
        let result: ProcessResult
        do {
            result = try await AgentStudioPerformanceTraceRecorder.withRestorePhaseScope(.restoreForegroundProbe) {
                try await DefaultProcessExecutor(performanceTraceRecorder: performanceTraceRecorder).execute(
                    command: "/bin/ps", args: ["-axo", "pid=,pgid=,tpgid="], cwd: nil, environment: nil)
            }
        } catch is CancellationError { throw CancellationError() } catch { return .init(samples: [], complete: false) }
        guard result.succeeded else { return .init(samples: [], complete: false) }
        let lines = result.stdout.split(separator: "\n")
        let rows = lines.compactMap { line -> (pid: Int32, group: Int32, foreground: Int32)? in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 3, let pid = Int32(fields[0]), let group = Int32(fields[1]),
                let foreground = Int32(fields[2])
            else { return nil }
            return (pid, group, foreground)
        }
        guard rows.count == lines.count else { return .init(samples: [], complete: false) }
        let leaderIds = Set(leaders.map(\.pid))
        let foregroundGroups = Set(rows.filter { leaderIds.contains($0.pid) && $0.foreground > 0 }.map(\.foreground))
        let selected = rows.filter { leaderIds.contains($0.pid) || foregroundGroups.contains($0.group) }
        var samples: [ForegroundProcessSample] = []
        for row in selected {
            try Task.checkCancellation()
            guard let sample = readNativeSample(pid: row.pid, readArguments: foregroundGroups.contains(row.group))
            else { return .init(samples: [], complete: false) }
            // A group change since ps invalidates this pass instead of calling a
            // background agent foreground from a mix of two snapshots.
            guard sample.processGroupId == row.group, sample.foregroundGroupId == row.foreground else {
                return .init(samples: [], complete: false)
            }
            samples.append(sample)
        }
        return .init(samples: samples, complete: true)
    }

    private static func readNativeSample(pid: Int32, readArguments: Bool) -> ForegroundProcessSample? {
        var information = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &information, size) == size,
            information.pbi_uid == geteuid(), information.pbi_pid == UInt32(pid)
        else { return nil }
        let incarnation = ProcessIncarnation(
            pid: pid, startSeconds: information.pbi_start_tvsec, startMicroseconds: information.pbi_start_tvusec)
        var argv0 = ""
        if readArguments {
            guard case .success(let buffer) = DarwinColdStartObserverSyscalls().readProcessArgumentsBuffer(pid: pid),
                let argument = ProcessArgumentsBufferParser.argumentVector(in: buffer)?.first,
                DarwinColdStartObserverSyscalls().leaderState(of: incarnation) == .sameIncarnationAlive
            else { return nil }
            argv0 = argument
        }
        return ForegroundProcessSample(
            incarnation: incarnation, processGroupId: Int32(information.pbi_pgid),
            foregroundGroupId: Int32(information.e_tpgid), argv0: argv0)
    }
}

private struct ForegroundZmxSessionControl: ZmxSessionControlling {
    let directory: String
    let bootId: String

    @concurrent nonisolated func observeSessionIdentity(_ sessionID: ZmxSessionID) async throws -> Data? {
        let path = "\(directory)/\(sessionID.rawValue)"
        if try ZmxSessionControl.endpointIsAbsent(path: path) { return nil }
        do { return try ZmxSessionControl.observe(path: path, bootID: bootId).encoded() } catch {
            if try ZmxSessionControl.endpointIsAbsent(path: path) { return nil }
            throw error
        }
    }

    func retireVerifiedSession(_ sessionID: ZmxSessionID, expectedIdentity: Data) async throws
        -> ZmxSessionCleanupStatus
    {
        // The observer is inspection-only; retirement remains the existing runtime owner's job.
        throw ZmxSessionControlFailure.unavailable
    }
}
