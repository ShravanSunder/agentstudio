import AgentStudioProgrammaticControl
import Foundation

extension AppCommandSpec {
    var ipcCommandListEntry: IPCCommandListEntry {
        IPCCommandListEntry(
            id: IPCCommandIdentifier(rawValue: command.rawValue),
            title: label,
            executionModes: ipcExposure.executionModes,
            targetKinds: ipcExposure.targetKinds,
            requiredPrivileges: ipcExposure.requiredPrivileges
        )
    }
}
