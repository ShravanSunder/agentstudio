import AppKit
import GhosttyKit

enum TerminalSurfaceAction: Equatable {
    enum SearchDirection: Equatable {
        case next
        case previous
    }

    case copyToClipboard
    case pasteFromClipboard
    case selectAll
    case scrollToBottom
    case scrollPageUp
    case jumpToPrompt(Int)
    case scrollToRow(Int)
    case startSearch
    case search(String)
    case navigateSearch(SearchDirection)
    case endSearch

    var bindingActionString: String {
        switch self {
        case .copyToClipboard:
            return "copy_to_clipboard"
        case .pasteFromClipboard:
            return "paste_from_clipboard"
        case .selectAll:
            return "select_all"
        case .scrollToBottom:
            return "scroll_to_bottom"
        case .scrollPageUp:
            return "scroll_page_up"
        case .jumpToPrompt(let delta):
            return "jump_to_prompt:\(delta)"
        case .scrollToRow(let row):
            return "scroll_to_row:\(row)"
        case .startSearch:
            return "start_search"
        case .search(let query):
            return "search:\(query)"
        case .navigateSearch(.next):
            return "navigate_search:next"
        case .navigateSearch(.previous):
            return "navigate_search:previous"
        case .endSearch:
            return "end_search"
        }
    }
}

@MainActor
protocol TerminalSurfaceActionPerforming: AnyObject {
    @discardableResult
    func performBindingAction(_ action: TerminalSurfaceAction) -> Bool
}

extension Ghostty.SurfaceView: TerminalSurfaceActionPerforming {
    @discardableResult
    func performBindingAction(_ action: TerminalSurfaceAction) -> Bool {
        guard let surface else { return false }
        let bindingActionString = action.bindingActionString
        return bindingActionString.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(bindingActionString.utf8.count))
        }
    }
}
