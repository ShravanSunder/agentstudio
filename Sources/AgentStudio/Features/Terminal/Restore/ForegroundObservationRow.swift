import AgentStudioCore
import Foundation
import GRDB

/// SQLite's typed shape is separate from the opaque interchange identity.
/// No argv or identity JSON is persisted; decoding uses the validated R1 codec.
enum ForegroundObservationRow {
    static func canStore(identity: ZmxSessionIdentity, sequence: UInt64) -> Bool {
        [
            sequence, identity.daemon.startSeconds, identity.daemon.startMicroseconds,
            identity.terminalLeader.startSeconds, identity.terminalLeader.startMicroseconds,
            identity.sessionCreatedAt,
        ].allSatisfy { Int64(exactly: $0) != nil }
    }

    static func load(paneId: UUID, in database: Database) throws -> PaneForegroundObservation? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM terminal_pane_foreground_observation WHERE pane_id = ?",
                arguments: [paneId.uuidString])
        else { return nil }
        guard let session = ZmxSessionID(restoring: row["zmx_session_id"]),
            let launch = UUID(uuidString: row["observer_launch_id"]),
            let program = ForegroundProgram(rawValue: row["program"]),
            let sequence = UInt64(exactly: row["sequence"] as Int64),
            let observedAt = timestampFormatter().date(from: row["observed_at"]),
            let identity = decodeIdentity(row)
        else { return nil }
        let bindingText: String? = row["binding_generation_id"]
        let bindingId = bindingText.flatMap(UUID.init(uuidString:))
        guard bindingText == nil || bindingId != nil else { return nil }
        return PaneForegroundObservation(
            paneId: paneId, zmxSessionId: session, sessionIdentity: identity,
            bindingGenerationId: bindingId, program: program, observerLaunchId: launch,
            sequence: sequence, observedAt: observedAt)
    }

    private static func decodeIdentity(_ row: Row) -> Data? {
        guard let daemonSeconds = UInt64(exactly: row["daemon_start_seconds"] as Int64),
            let daemonMicros = UInt64(exactly: row["daemon_start_microseconds"] as Int64),
            let leaderSeconds = UInt64(exactly: row["leader_start_seconds"] as Int64),
            let leaderMicros = UInt64(exactly: row["leader_start_microseconds"] as Int64),
            let createdAt = UInt64(exactly: row["session_created_at"] as Int64),
            let daemonPid = Int32(exactly: row["daemon_pid"] as Int64),
            let leaderPid = Int32(exactly: row["leader_pid"] as Int64),
            let group = Int32(exactly: row["process_group_id"] as Int64)
        else { return nil }
        let identity = ZmxSessionIdentity(
            version: row["identity_version"], bootID: row["boot_id"],
            daemon: .init(pid: daemonPid, startSeconds: daemonSeconds, startMicroseconds: daemonMicros),
            terminalLeader: .init(pid: leaderPid, startSeconds: leaderSeconds, startMicroseconds: leaderMicros),
            processGroupID: group, sessionCreatedAt: createdAt)
        guard let encoded = try? identity.encoded(), (try? ZmxSessionIdentity.decode(encoded)) != nil else {
            return nil
        }
        return encoded
    }

    static func write(_ observation: PaneForegroundObservation, identity: ZmxSessionIdentity, in database: Database)
        throws
    {
        try database.execute(
            sql: """
                INSERT OR REPLACE INTO terminal_pane_foreground_observation (
                    pane_id,zmx_session_id,binding_generation_id,program,observer_launch_id,sequence,observed_at,
                    identity_version,boot_id,daemon_pid,daemon_start_seconds,daemon_start_microseconds,
                    leader_pid,leader_start_seconds,leader_start_microseconds,process_group_id,session_created_at
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            arguments: [
                observation.paneId.uuidString, observation.zmxSessionId.rawValue,
                observation.bindingGenerationId?.uuidString, observation.program.rawValue,
                observation.observerLaunchId.uuidString, Int64(observation.sequence),
                timestampFormatter().string(from: observation.observedAt),
                identity.version, identity.bootID, identity.daemon.pid, Int64(identity.daemon.startSeconds),
                Int64(identity.daemon.startMicroseconds), identity.terminalLeader.pid,
                Int64(identity.terminalLeader.startSeconds), Int64(identity.terminalLeader.startMicroseconds),
                identity.processGroupID, Int64(identity.sessionCreatedAt),
            ])
    }

    private static func timestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
