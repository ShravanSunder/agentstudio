import Foundation

package enum PaneFramePublicationDestination: Equatable {
    case tabContainer
    case drawerContainer
}

package enum PaneFramePublicationPolicy {
    package static func destinations(useDrawerFramePreference: Bool) -> [PaneFramePublicationDestination] {
        if useDrawerFramePreference {
            return [.drawerContainer]
        }
        return [.tabContainer]
    }
}
