import Foundation

enum SQLitePaneContentTypeStorage {
    static let terminal = "terminal"
    static let browser = "browser"
    static let diff = "diff"
    static let editor = "editor"
    static let review = "review"
    static let agent = "agent"
    static let codeViewer = "codeViewer"
    static let pluginPrefix = "plugin:"

    static func storageValue(for contentType: PaneContentType) -> String {
        switch contentType {
        case .terminal:
            terminal
        case .browser:
            browser
        case .diff:
            diff
        case .editor:
            editor
        case .review:
            review
        case .agent:
            agent
        case .codeViewer:
            codeViewer
        case .plugin(let pluginIdentifier):
            "\(pluginPrefix)\(pluginIdentifier)"
        }
    }
}
