import Foundation

@MainActor
struct TerminalRestoreRuntime {
    struct ZmxAttachDiagnostics: Sendable {
        let paneId: UUID
        let sessionId: String
        let zmxDir: String
        let socketPath: String
        let socketPathLength: Int
        let maxSocketPathLength: Int
        let zmxPath: String

        var socketPathHeadroom: Int {
            maxSocketPathLength - socketPathLength
        }
    }

    let sessionConfiguration: SessionConfiguration

    /// Return the exact durable identity stored with the terminal pane.
    /// Restoration never derives, validates against pane shape, or rewrites it.
    func zmxSessionID(for pane: Pane) -> ZmxSessionID? {
        guard pane.provider == .zmx else { return nil }
        return pane.terminalState?.zmxSessionID
    }

    func zmxAttachCommand(for pane: Pane) -> String? {
        guard sessionConfiguration.isOperational else { return nil }
        guard let sessionID = zmxSessionID(for: pane) else { return nil }
        guard let zmxPath = sessionConfiguration.zmxPath else { return nil }
        return ZmxBackend.buildAttachCommand(
            zmxPath: zmxPath,
            sessionID: sessionID,
            shell: SessionConfiguration.defaultShell()
        )
    }

    func zmxAttachDiagnostics(for pane: Pane) -> ZmxAttachDiagnostics? {
        guard sessionConfiguration.isOperational else { return nil }
        guard let sessionID = zmxSessionID(for: pane) else { return nil }
        guard let zmxPath = sessionConfiguration.zmxPath else { return nil }

        let socketPath = "\(sessionConfiguration.zmxDir)/\(sessionID.rawValue)"
        return ZmxAttachDiagnostics(
            paneId: pane.id,
            sessionId: sessionID.rawValue,
            zmxDir: sessionConfiguration.zmxDir,
            socketPath: socketPath,
            socketPathLength: socketPath.count,
            maxSocketPathLength: 103,
            zmxPath: zmxPath
        )
    }
}
