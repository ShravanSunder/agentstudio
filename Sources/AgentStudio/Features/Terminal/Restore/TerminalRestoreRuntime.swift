import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

@MainActor
package struct TerminalRestoreRuntime {
    package struct ZmxAttachDiagnostics: Sendable {
        package let paneId: UUID
        package let sessionId: String
        let zmxDir: String
        let socketPath: String
        package let socketPathLength: Int
        package let maxSocketPathLength: Int
        let zmxPath: String

        package var socketPathHeadroom: Int {
            maxSocketPathLength - socketPathLength
        }
    }

    let sessionConfiguration: SessionConfiguration

    package init(sessionConfiguration: SessionConfiguration) {
        self.sessionConfiguration = sessionConfiguration
    }

    /// Return the exact durable identity stored with the terminal pane.
    /// Restoration never derives, validates against pane shape, or rewrites it.
    func zmxSessionID(for pane: Pane) -> ZmxSessionID? {
        guard pane.provider == .zmx else { return nil }
        return pane.terminalState?.zmxSessionID
    }

    package func zmxAttachCommand(for pane: Pane) -> String? {
        guard sessionConfiguration.isOperational else { return nil }
        guard let sessionID = zmxSessionID(for: pane) else { return nil }
        guard let zmxPath = sessionConfiguration.zmxPath else { return nil }
        return ZmxBackend.buildAttachCommand(
            zmxPath: zmxPath,
            sessionID: sessionID,
            shell: SessionConfiguration.defaultShell()
        )
    }

    package func zmxAttachDiagnostics(for pane: Pane) -> ZmxAttachDiagnostics? {
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
