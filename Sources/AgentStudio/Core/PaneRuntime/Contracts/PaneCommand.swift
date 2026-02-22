import Foundation

struct PaneCommandEnvelope: Sendable {
    let commandId: UUID
    let correlationId: UUID?
    let targetPaneId: PaneId
    let command: PaneCommand
    let timestamp: ContinuousClock.Instant
}

protocol PaneKindCommand: Sendable {
    var commandName: String { get }
}

enum PaneCommand: Sendable {
    case activate
    case deactivate
    case prepareForClose
    case requestSnapshot
    case terminal(TerminalCommand)
    case browser(BrowserCommand)
    case diff(DiffCommand)
    case editor(EditorCommand)
    case plugin(any PaneKindCommand)
}

enum TerminalCommand: Sendable {
    case sendInput(String)
    case resize(cols: Int, rows: Int)
    case clearScrollback
}

enum BrowserCommand: Sendable {
    case navigate(url: URL)
    case reload(hard: Bool)
    case stop
}

enum DiffCommand: Sendable {
    case loadDiff(DiffArtifact)
    case approveHunk(hunkId: String)
    case rejectHunk(hunkId: String, reason: String?)
}

enum EditorCommand: Sendable {
    case openFile(path: String, line: Int?, column: Int?)
    case save
    case revert
}
