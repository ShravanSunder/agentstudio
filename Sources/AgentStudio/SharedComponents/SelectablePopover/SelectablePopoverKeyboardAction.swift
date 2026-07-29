import Foundation

package enum SelectablePopoverKeyboardAction<ItemID: Equatable>: Equatable {
    case dismiss
    case select(ItemID)
    case auxiliary(ItemID)
    case highlight(ItemID)
    case consume
    case passthrough
}
