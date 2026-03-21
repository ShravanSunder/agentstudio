import Foundation

enum AppEvent: Sendable {
    case terminalProcessTerminated(worktreeId: UUID?, exitCode: Int32?)
    case repairSurfaceRequested(paneId: UUID)
    case worktreeBellRang(paneId: UUID)
}
