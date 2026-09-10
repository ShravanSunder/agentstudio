import Foundation

package protocol ZmxSessionControlling: Sendable {
    /// Nil means the exact endpoint is positively absent, not a failed inspection.
    func observeSessionIdentity(_ sessionID: ZmxSessionID) async throws -> Data?
    func retireVerifiedSession(_ sessionID: ZmxSessionID, expectedIdentity: Data) async throws
        -> ZmxSessionCleanupStatus
}

/// Local cleanup evidence, never terminal output or a process-supervision graph.
struct ZmxSessionIdentity: Codable, Equatable, Sendable {
    let version: Int
    let bootID: String
    let daemon: ZmxProcessIncarnation
    let terminalLeader: ZmxProcessIncarnation
    let processGroupID: Int32
    let sessionCreatedAt: UInt64

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        let identity = try JSONDecoder().decode(Self.self, from: data)
        guard identity.version == 1, !identity.bootID.isEmpty,
            identity.daemon.pid > 1, identity.terminalLeader.pid > 1,
            identity.daemon.pid != identity.terminalLeader.pid,
            identity.processGroupID == identity.terminalLeader.pid,
            identity.daemon.startMicroseconds < 1_000_000,
            identity.terminalLeader.startMicroseconds < 1_000_000
        else { throw ZmxSessionControlFailure.invalidIdentity }
        return identity
    }
}

struct ZmxProcessIncarnation: Codable, Equatable, Sendable {
    let pid: Int32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

package enum ZmxSessionCleanupStatus: Equatable, Sendable {
    case pending
    case completed
}

package enum ZmxSessionControlFailure: String, Error, Sendable {
    case invalidIdentity
    case unavailable
    case invalidSocketPath
    case timeout
    case invalidResponse
    case identityMismatch
    case processUnverifiable
    case unexpectedProcessParent
    case unexpectedProcessGroup
    case nativeAttachmentPresent
    case awaitingProcessExit
}
