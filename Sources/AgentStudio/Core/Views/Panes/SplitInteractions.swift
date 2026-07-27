import Foundation

package struct SplitDropPayload: Equatable, Codable {
    package enum Kind: Equatable, Codable {
        case existingTab(tabId: UUID)
        case existingPane(paneId: UUID, sourceTabId: UUID)
        case newTerminal
    }

    package let kind: Kind
}

package enum SplitFocusDirection: Equatable, Hashable {
    case left
    case right
    case up
    case down
}
