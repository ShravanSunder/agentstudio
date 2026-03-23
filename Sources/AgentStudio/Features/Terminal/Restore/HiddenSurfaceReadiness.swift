import Foundation

enum HiddenSurfaceRevealState: Equatable, Sendable {
    case restoring
    case reveal
    case failed
}

enum HiddenSurfaceReadiness {
    static func revealState(
        processExited: Bool,
        startupWindowElapsed: Bool
    ) -> HiddenSurfaceRevealState {
        if processExited {
            return .failed
        }
        if startupWindowElapsed {
            return .reveal
        }
        return .restoring
    }

    static func focusedStateAfterOcclusion(_ wasFocused: Bool) -> Bool {
        guard wasFocused else { return false }
        return false
    }
}
