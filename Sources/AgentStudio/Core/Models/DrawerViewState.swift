import Foundation

enum DrawerViewState: Equatable {
    case empty
    case populated(DrawerView)
    case missingForNonEmptyDrawer(drawerId: DrawerId)

    var drawerView: DrawerView? {
        switch self {
        case .empty:
            DrawerView()
        case .populated(let drawerView):
            drawerView
        case .missingForNonEmptyDrawer:
            nil
        }
    }
}
