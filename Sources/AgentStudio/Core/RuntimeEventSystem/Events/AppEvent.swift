import Foundation

enum AppEvent: Sendable {
    case terminalProcessTerminated(paneId: UUID)
    case terminalProcessTerminationHandled(paneId: UUID)
    case worktreeBellRang(paneId: UUID)
}
