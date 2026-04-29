import Foundation

struct SplitDropPayload: Equatable, Codable {
    enum Kind: Equatable, Codable {
        case existingTab(tabId: UUID)
        case existingPane(paneId: UUID, sourceTabId: UUID)
        case newTerminal
    }

    let kind: Kind
}

enum SplitFocusDirection: Equatable, Hashable {
    case left
    case right
    case up
    case down
}
