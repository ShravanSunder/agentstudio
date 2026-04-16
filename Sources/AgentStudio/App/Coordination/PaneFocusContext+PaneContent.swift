import Foundation

extension PaneFocusContext.PaneKind {
    init(content: PaneContent?) {
        switch content {
        case .terminal:
            self = .terminal
        case .webview:
            self = .webview
        case .bridgePanel:
            self = .bridge
        case .codeViewer:
            self = .codeViewer
        case .unsupported, .none:
            self = .unknown
        }
    }
}
