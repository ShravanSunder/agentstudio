import Foundation

struct RuntimeCommandEnvelope: Sendable {
    let commandId: UUID
    let correlationId: UUID?
    let targetPaneId: PaneId
    let command: PaneRuntimeCommand
    let timestamp: ContinuousClock.Instant
}

protocol RuntimeKindCommand: Sendable {}

enum PaneRuntimeCommand: Sendable {
    case activate
    case deactivate
    case prepareForClose
    case requestSnapshot
    case terminal(TerminalCommand)
    case browser(BrowserCommand)
    case diff(DiffCommand)
    case editor(EditorCommand)
    case plugin(any RuntimeKindCommand)
}

extension PaneRuntimeCommand {
    var requiredCapability: PaneCapability {
        switch self {
        case .terminal:
            return .input
        case .browser:
            return .navigation
        case .diff:
            return .diffReview
        case .editor:
            return .editorActions
        case .plugin(let pluginCommand):
            return .plugin(String(describing: type(of: pluginCommand)))
        case .activate, .deactivate, .prepareForClose, .requestSnapshot:
            return .input
        }
    }
}

enum TerminalCommand: Sendable {
    case sendInput(String)
    case resize(cols: Int, rows: Int)
    case clearScrollback
    case scrollToBottom
    case scrollPageUp
    case jumpToPrompt(delta: Int)
}

enum BrowserCommand: Sendable {
    case navigate(url: URL)
    case reload(hard: Bool)
    case stop
}

enum DiffCommand: Sendable {
    case loadDiff(DiffArtifact)
}

enum EditorCommand: Sendable {
    case openFile(path: String, line: Int?, column: Int?)
    case save
    case revert
}
