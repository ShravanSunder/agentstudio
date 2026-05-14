import Foundation

enum DropSizingModeResolver {
    static func mode(for target: DropTarget, isShiftHeld: Bool) -> DropSizingMode {
        if isShiftHeld { return .proportional }

        switch target {
        case .paneSplit:
            return .halveTarget
        case .paneSlot, .paneNewRow:
            return .proportional
        }
    }
}
