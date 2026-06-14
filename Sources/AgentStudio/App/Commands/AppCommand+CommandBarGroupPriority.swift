import Foundation

extension AppCommand {
    enum CommandBarGroupPriority {
        static let terminal = 0
        static let pane = 1
        static let focus = 2
        static let tab = 3
        static let repo = 4
        static let window = 5
        static let webview = 6
        static let auth = 7
        static let miscellaneous = 8
    }
}
