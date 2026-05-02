import Foundation

struct SelectablePopoverKeyboardItem<ItemID: Hashable>: Equatable, Identifiable {
    let id: ItemID
    let shortcutNumber: Int?
    let supportsAuxiliaryAction: Bool

    init(
        id: ItemID,
        shortcutNumber: Int? = nil,
        supportsAuxiliaryAction: Bool = false
    ) {
        self.id = id
        self.shortcutNumber = shortcutNumber
        self.supportsAuxiliaryAction = supportsAuxiliaryAction
    }
}
