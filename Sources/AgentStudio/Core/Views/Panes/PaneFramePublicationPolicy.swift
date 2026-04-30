import Foundation

enum PaneFramePublicationDestination: Equatable {
    case tabContainer
    case drawerContainer
}

enum PaneFramePublicationPolicy {
    static func destinations(useDrawerFramePreference: Bool) -> [PaneFramePublicationDestination] {
        if useDrawerFramePreference {
            return [.drawerContainer]
        }
        return [.tabContainer]
    }
}
