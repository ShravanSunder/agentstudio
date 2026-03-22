import Foundation

enum AppEvent: Sendable {
    case terminalProcessTerminated(worktreeId: UUID?, exitCode: Int32?)
    case worktreeBellRang(paneId: UUID)
}
