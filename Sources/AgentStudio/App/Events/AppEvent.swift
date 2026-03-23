import Foundation

enum AppEvent: Sendable {
    case terminalProcessTerminated(paneId: UUID, exitCode: Int32?)
    case worktreeBellRang(paneId: UUID)
}
