import Foundation
import Observation

@MainActor
@Observable
final class CommandBarSurfaceAtom {
    private(set) var activeScope: CommandBarScope?

    var isActive: Bool {
        activeScope != nil
    }

    func present(scope: CommandBarScope) {
        activeScope = scope
    }

    func dismiss() {
        activeScope = nil
    }
}
